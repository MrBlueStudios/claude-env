// Pictures and audio: uploaded into the crew-vault repo, then announced by an issue like any share.
import { REPO, explain, sendShare } from "./app.js";

export const MAX_BYTES = 20 * 1024 * 1024; // shortcut: one JSON PUT per file, so GitHub's contents API sets the ceiling; upgrade to the git data API if recordings outgrow it
const IMAGE = ["png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "bmp", "heic"];
const AUDIO = ["mp3", "m4a", "wav", "ogg", "oga", "opus", "aac", "flac", "amr", "3gp"];

export function fileKind(name = "", type = "") {
  if (type.startsWith("image/")) return "image-file";
  if (type.startsWith("audio/")) return "audio-file";
  const ext = /\.([a-z0-9]+)$/i.exec(name)?.[1]?.toLowerCase();
  return IMAGE.includes(ext) ? "image-file" : AUDIO.includes(ext) ? "audio-file" : null;
}

export function safeName(name = "") {
  const base = String(name).split(/[\\/]/).pop();
  const ext = /\.([A-Za-z0-9]{1,5})$/.exec(base)?.[1]?.toLowerCase();
  const stem = (ext ? base.slice(0, -ext.length - 1) : base).replace(/[^A-Za-z0-9._-]+/g, "-").replace(/-+/g, "-").slice(0, 50);
  return `${/[A-Za-z0-9]/.test(stem) ? stem : "file"}${ext ? `.${ext}` : ""}`;
}

// The path and id are fixed once, so a retry of the same share reuses both and never duplicates it.
export function prepareFile(file, now = new Date(), id = crypto.randomUUID()) {
  return { file, name: file.name, kind: fileKind(file.name, file.type), id, path: `inbox-files/${now.toISOString().slice(0, 10)}-${id.slice(0, 8)}-${safeName(file.name)}` };
}

export function buildFileIssue({ name, kind, path, id }, via) {
  const title = Array.from(String(name).replace(/\s+/g, " ").trim()).slice(0, 120).join("") || "file";
  return { title, body: `${title}\n\nkind: ${kind}\nfile: ${path}\nid: ${id}\nvia: ${via}`, labels: ["inbox"] };
}

export function toBase64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

export async function putFile(fetchFn, token, path, bytes, message) {
  let res;
  try {
    res = await fetchFn(`https://api.github.com/repos/${REPO}/contents/${path}`, {
      method: "PUT",
      headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "Content-Type": "application/json" },
      body: JSON.stringify({ message, content: toBase64(bytes) }),
    });
  } catch (err) {
    return { status: "retry", reason: `${explain("network")} (${err.message})` };
  }
  if (res.status === 201 || res.status === 422) return { status: "sent" }; // 422: the path is unique per share, so an earlier try saved it
  if (res.status === 401) return { status: "auth" };
  if (res.status === 403 || res.status === 404) {
    return { status: "scope", reason: `${res.status}: GitHub refused the upload. The token can open issues but not store files: edit it on GitHub and set Contents to Read and write.` };
  }
  if (res.status === 429 || res.status >= 500) return { status: "retry", reason: explain(res.status) };
  return { status: "error", reason: explain(res.status) };
}

export async function sendFile(fetchFn, token, prepared, via, { sleep } = {}) {
  const { file, kind, path } = prepared;
  if (!kind) return { status: "error", reason: "Only pictures and audio can be sent as files. Share a video as a link instead." };
  if (file.size > MAX_BYTES) return { status: "error", reason: `This file is too big (limit ${MAX_BYTES / 1024 / 1024} MB).` };
  const up = await putFile(fetchFn, token, path, new Uint8Array(await file.arrayBuffer()), `inbox: add ${path.split("/").pop()}`);
  if (up.status !== "sent") return up;
  const issue = buildFileIssue(prepared, via);
  return { ...(await sendShare(fetchFn, token, issue, sleep)), issue };
}
