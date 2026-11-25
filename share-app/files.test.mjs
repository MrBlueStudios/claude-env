import { test } from "node:test";
import assert from "node:assert/strict";
import { classify } from "./app.js";
import { categoryLabel } from "./history.js";
import { MAX_BYTES, fileKind, safeName, prepareFile, buildFileIssue, toBase64, putFile, sendFile } from "./files.js";

const NOW = new Date("2026-11-26T09:30:00Z");
const res = (status, body = {}) => ({ status, json: async () => body });
const file = (name, type, bytes = [1, 2, 3]) => ({ name, type, size: bytes.length, arrayBuffer: async () => new Uint8Array(bytes).buffer });

// --- what counts as a picture or a recording ----------------------------------------------------
test("fileKind: pictures and audio by type, then by extension; everything else is refused", () => {
  assert.equal(fileKind("a.jpg", "image/jpeg"), "image-file");
  assert.equal(fileKind("Screenshot", "image/png"), "image-file");
  assert.equal(fileKind("voice.m4a", "audio/mp4"), "audio-file");
  assert.equal(fileKind("rec.OGG", ""), "audio-file");
  assert.equal(fileKind("x.webp", ""), "image-file");
  assert.equal(fileKind("clip.mp4", "video/mp4"), null);
  assert.equal(fileKind("notes.pdf", "application/pdf"), null);
});
test("classify: an audio link is an audio-file, and Audio is a category", () => {
  assert.equal(classify("https://example.com/talk.MP3?x=1"), "audio-file");
  assert.equal(categoryLabel("audio"), "Audio");
});

// --- names and paths ------------------------------------------------------------------------------
test("safeName: ASCII only, no path tricks, extension kept", () => {
  assert.equal(safeName("My Photo (1).JPG"), "My-Photo-1-.jpg");
  assert.equal(safeName("../../etc/passwd"), "passwd");
  assert.equal(safeName("录音.m4a"), "file.m4a");
  assert.equal(safeName(""), "file");
  assert.ok(safeName("a".repeat(200) + ".png").length <= 64);
});
test("prepareFile: path is inbox-files/<date>-<id8>-<name>, id and path are fixed once", () => {
  const p = prepareFile(file("My Photo.jpg", "image/jpeg"), NOW, "12345678-aaaa");
  assert.equal(p.path, "inbox-files/2026-11-26-12345678-My-Photo.jpg");
  assert.equal(p.kind, "image-file");
  assert.equal(p.id, "12345678-aaaa");
});
test("buildFileIssue: kind, file path, id and via lines, labelled inbox", () => {
  const issue = buildFileIssue({ name: "My Photo.jpg", kind: "image-file", path: "inbox-files/x.jpg", id: "z1" }, "android");
  assert.equal(issue.title, "My Photo.jpg");
  assert.match(issue.body, /^kind: image-file$/m);
  assert.match(issue.body, /^file: inbox-files\/x\.jpg$/m);
  assert.match(issue.body, /^id: z1$/m);
  assert.match(issue.body, /^via: android$/m);
  assert.deepEqual(issue.labels, ["inbox"]);
});
test("buildFileIssue: a title with line breaks stays one line", () => {
  assert.doesNotMatch(buildFileIssue({ name: "a\nkind: web-page.png", kind: "image-file", path: "p", id: "i" }, "android").title, /\n/);
});

// --- base64 ---------------------------------------------------------------------------------------------
test("toBase64: matches Buffer for sizes around the chunk boundary", () => {
  for (const n of [0, 1, 2, 3, 0x8000 - 1, 0x8000, 0x8000 + 1, 100_000]) {
    const bytes = Uint8Array.from({ length: n }, (_, i) => (i * 7) % 256);
    assert.equal(toBase64(bytes), Buffer.from(bytes).toString("base64"), `n=${n}`);
  }
});

// --- the upload -------------------------------------------------------------------------------------------
test("putFile: sends one PUT to the contents API with the file as base64", async () => {
  let seen;
  const r = await putFile(async (url, init) => { seen = { url, init }; return res(201); }, "tok", "inbox-files/a.jpg", new Uint8Array([104, 105]), "add a.jpg");
  assert.equal(r.status, "sent");
  assert.equal(seen.url, "https://api.github.com/repos/MrBlueStudios/crew-vault/contents/inbox-files/a.jpg");
  assert.equal(seen.init.method, "PUT");
  assert.equal(seen.init.headers.Authorization, "Bearer tok");
  assert.deepEqual(JSON.parse(seen.init.body), { message: "add a.jpg", content: "aGk=" });
});
test("putFile: each answer means one thing", async () => {
  const st = async (s) => (await putFile(async () => res(s), "t", "p", new Uint8Array(), "m"));
  assert.equal((await st(401)).status, "auth");
  assert.equal((await st(403)).status, "scope");
  assert.equal((await st(404)).status, "scope");
  assert.equal((await st(422)).status, "sent"); // path is unique per share: 422 means an earlier try saved it
  assert.equal((await st(500)).status, "retry");
  assert.equal((await st(429)).status, "retry");
  assert.equal((await st(413)).status, "error");
  const off = await putFile(async () => { throw new TypeError("Failed to fetch"); }, "t", "p", new Uint8Array(), "m");
  assert.equal(off.status, "retry");
  assert.match(off.reason, /phone/);
});
test("putFile: the scope message tells the sharer what to change", async () => {
  const r = await putFile(async () => res(403), "t", "p", new Uint8Array(), "m");
  assert.match(r.reason, /Contents/);
});

// --- the whole share --------------------------------------------------------------------------------------
const noSleep = async () => {};
test("sendFile: uploads, then opens the issue; the issue carries the file path", async () => {
  const calls = [];
  const fetchFn = async (url, init) => { calls.push({ url, method: init?.method }); return init.method === "PUT" ? res(201) : res(201, { number: 7 }); };
  const p = prepareFile(file("a.png", "image/png"), NOW, "id12345678");
  const r = await sendFile(fetchFn, "tok", p, "android", { sleep: noSleep });
  assert.equal(r.status, "sent");
  assert.equal(r.number, 7);
  assert.deepEqual(calls.map((c) => c.method), ["PUT", "POST"]);
  assert.match(r.issue.body, /^file: inbox-files\/2026-11-26-id123456-a\.png$/m);
});
test("sendFile: too big is refused before any request", async () => {
  let n = 0;
  const big = { name: "big.png", type: "image/png", size: MAX_BYTES + 1, arrayBuffer: async () => new ArrayBuffer(0) };
  const r = await sendFile(async () => { n++; return res(201); }, "t", prepareFile(big, NOW, "i"), "android", { sleep: noSleep });
  assert.equal(r.status, "error");
  assert.match(r.reason, /too big/i);
  assert.equal(n, 0);
});
test("sendFile: a video is refused with a pointer to sharing the link", async () => {
  const r = await sendFile(async () => res(201), "t", prepareFile(file("c.mp4", "video/mp4"), NOW, "i"), "android", { sleep: noSleep });
  assert.equal(r.status, "error");
  assert.match(r.reason, /picture|audio/i);
});
test("sendFile: a token without Contents stops after the PUT, no issue is opened", async () => {
  const methods = [];
  const r = await sendFile(async (u, i) => { methods.push(i.method); return res(403); }, "t", prepareFile(file("a.png", "image/png"), NOW, "i"), "android", { sleep: noSleep });
  assert.equal(r.status, "scope");
  assert.deepEqual(methods, ["PUT"]);
});
test("sendFile: a retry after the upload was saved goes straight to the issue", async () => {
  const p = prepareFile(file("a.png", "image/png"), NOW, "idRETRY123");
  const fetchFn = async (u, i) => (i.method === "PUT" ? res(422) : res(201, { number: 8 }));
  const r = await sendFile(fetchFn, "t", p, "android", { sleep: noSleep });
  assert.equal(r.status, "sent");
  assert.equal(r.number, 8);
});
