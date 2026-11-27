// The Crew inbox screen: a paste box, the shares by category, and how far each one got.
import { buildIssue, sendShare, readToken, writeToken, savePending, loadPending, clearPending } from "./app.js";
import { prepareFile, sendFile } from "./files.js";
import { fetchHistory, addComment, groupShares, mergeLocal, entryFromIssue, ago, typeLabel, categoryLabel, categoryColor } from "./history.js";

const $ = (id) => document.getElementById(id);
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}
let store = null;
try { store = window.localStorage; } catch {}

// What this phone just sent, shown until GitHub's list (4-5 s behind) includes it.
const LOG_KEY = "crewShareLog";
const readLog = () => { try { return JSON.parse(store.getItem(LOG_KEY)) || []; } catch { return []; } };
const writeLog = (entries) => { try { store.setItem(LOG_KEY, JSON.stringify(entries.slice(0, 30))); } catch {} };

// Files waiting to be uploaded: picked on this page, or left in the Cache by the phone's share menu.
let queued = [];
let uploading = false;
const FILE_CACHE = "crew-share-files";

async function takeSharedFiles() {
  try {
    const cache = await caches.open(FILE_CACHE);
    for (const req of await cache.keys()) {
      const r = await cache.match(req);
      const f = new File([await r.blob()], decodeURIComponent(r.headers.get("x-name") || "file"), { type: r.headers.get("content-type") || "" });
      queued.push({ ...prepareFile(f, new Date(r.headers.get("x-at") || Date.now()), r.headers.get("x-id") || undefined), cacheKey: req });
    }
  } catch {}
}
const dropFromCache = async (p) => { try { if (p.cacheKey) await (await caches.open(FILE_CACHE)).delete(p.cacheKey); } catch {} };

let shares = [];
let filter = "all";

const clock = (iso) => {
  const d = new Date(iso);
  const t = d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  return d.toDateString() === new Date().toDateString() ? t : `${d.toLocaleDateString([], { weekday: "short", day: "numeric", month: "short" })} ${t}`;
};
const host = (url) => { try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return ""; } };

// Shares that got a caption from this phone, so the box doesn't come back before /inbox has read it.
const CAP_KEY = "crewShareCaptioned";
const captioned = () => { try { return JSON.parse(store.getItem(CAP_KEY)) || []; } catch { return []; } };

function captionBox(e) {
  const box = el("form", "caption");
  if (captioned().includes(e.number)) { box.append(el("p", "note", "Caption sent ✓ Claude reads it on the next /inbox run.")); return box; }
  const ta = el("textarea");
  ta.id = `caption-${e.number}`;
  ta.rows = 3;
  ta.placeholder = "Paste the caption or a short description";
  const label = el("label", null, "This one needs its caption, because the site asks for a login. Next time use the app's Share button, not Copy link: it sends the title along.");
  label.htmlFor = ta.id;
  const send = el("button", "primary", "Send caption");
  send.type = "submit";
  const msg = el("p", "note");
  box.append(label, ta, send, msg);
  box.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const r = await addComment(fetch, readToken(), e.number, ta.value);
    if (r.status === "sent") {
      try { store.setItem(CAP_KEY, JSON.stringify([...captioned(), e.number])); } catch {}
      return render();
    }
    if (r.status === "auth") { writeToken(""); return showToken("GitHub refused the token. Paste a new one."); }
    msg.textContent = r.reason;
  });
  return box;
}

function card(e, showAuthor) {
  const needs = e.status.key === "needs-you";
  const node = e.href && !needs ? el("a", "card item") : el("div", "card item");
  if (e.href && !needs) { node.href = e.href; node.target = "_blank"; node.rel = "noopener"; }
  node.style.setProperty("--dot", categoryColor(e.platform));
  node.append(el("p", "title", e.title));
  if (e.url) node.append(el("p", "host", host(e.url)));
  const meta = el("div", "meta");
  if (typeLabel(e.type)) meta.append(el("span", "badge", typeLabel(e.type)));
  meta.append(el("span", "when", `${clock(e.createdAt)} · ${ago(e.createdAt)}`));
  meta.append(el("span", `pill tone-${e.status.tone}`, e.status.label));
  if (showAuthor && e.author) meta.append(el("span", "who", e.author));
  node.append(meta);
  if (needs) node.append(captionBox(e));
  return node;
}

function render() {
  const all = mergeLocal(shares, readLog());
  const groups = groupShares(all);
  if (filter !== "all" && !groups.some((g) => g.platform === filter)) filter = "all";

  const chips = $("chips");
  chips.replaceChildren();
  chips.hidden = groups.length === 0;
  const chip = (key, label, count) => {
    const b = el("button", "chip", label);
    b.type = "button";
    b.setAttribute("aria-pressed", String(filter === key));
    b.append(el("span", "count", String(count)));
    b.addEventListener("click", () => { filter = key; render(); });
    return b;
  };
  chips.append(chip("all", "All", all.length), ...groups.map((g) => chip(g.platform, g.label, g.items.length)));

  const authors = new Set(all.map((e) => e.author).filter(Boolean));
  const list = $("list");
  list.replaceChildren();
  for (const g of groups.filter((g) => filter === "all" || g.platform === filter)) {
    const section = el("section", "group");
    section.style.setProperty("--dot", g.color);
    const h = el("h2", null, g.label);
    h.append(el("span", "count", String(g.items.length)));
    section.append(h, ...g.items.map((e) => card(e, authors.size > 1)));
    list.append(section);
  }
  $("empty").hidden = all.length > 0 || !readToken();
}

function banner(text, { tone = "", share = "", retry = false } = {}) {
  const b = $("banner");
  b.hidden = text == null;
  b.className = tone;
  $("banner-text").textContent = text ?? "";
  $("banner-share").textContent = share;
  $("banner-share").hidden = !share;
  $("retry-button").hidden = !retry;
}
const shareText = (issue) => issue.body.split("\n\nkind:")[0];

function showToken(why) {
  $("token").hidden = false;
  if (why) $("token-why").textContent = why;
  for (const id of ["composer", "refresh", "chips", "list", "empty", "note"]) $(id).hidden = true;
}
function showMain() {
  $("token").hidden = true;
  $("composer").hidden = false;
  $("refresh").hidden = false;
  $("list").hidden = false;
}

async function loadList() {
  const token = readToken();
  if (!token) return;
  $("refresh").classList.add("spin");
  const r = await fetchHistory(fetch, token);
  $("refresh").classList.remove("spin");
  if (r.status === "auth") { writeToken(""); return showToken("GitHub refused the token. Paste a new one."); }
  $("note").hidden = r.status === "ok";
  if (r.status === "error") $("note").textContent = `Couldn't refresh the list. ${r.reason}`;
  else {
    shares = r.shares;
    writeLog(readLog().filter((e) => Date.now() - Date.parse(e.createdAt) < 15 * 60_000 && !shares.some((s) => s.id === e.id)));
  }
  render();
}

async function sendFiles() {
  if (uploading) return; // the running loop also takes files added meanwhile
  uploading = true;
  const sent = [];
  const problems = [];
  while (queued.length) {
    if (!readToken()) { uploading = false; return showToken("Paste your token and the file will be sent."); }
    const p = queued[0];
    banner(`Uploading ${p.name}… (${sent.length + 1} of ${sent.length + queued.length})`);
    const r = await sendFile(fetch, readToken(), p, "android");
    if (r.status === "sent") {
      queued.shift();
      dropFromCache(p);
      const entry = entryFromIssue(r.issue, r.number, new Date().toISOString());
      writeLog([entry, ...readLog()]);
      sent.push(`#${r.number} ${categoryLabel(entry.platform)}`);
      render();
    } else if (r.status === "error") {
      queued.shift();
      dropFromCache(p);
      problems.push(`${p.name}: ${r.reason}`);
    } else {
      // auth wipes the token; scope and retry keep the file queued for the Retry button.
      uploading = false;
      if (r.status === "auth") { writeToken(""); showToken("GitHub refused the token. Paste a new one; your file is kept."); banner(null); return; }
      return banner(`${r.reason} Your file is kept.`, { tone: "err", share: p.name, retry: true });
    }
  }
  uploading = false;
  banner([sent.length && `Sent ✓ ${sent.join(", ")}.`, ...problems].filter(Boolean).join(" "), { tone: problems.length ? "err" : "ok" });
  if (sent.length) setTimeout(loadList, 6000);
}

async function send(issue) {
  if (!readToken()) { savePending(store, issue); return showToken(); }
  savePending(store, issue);
  banner("Sending…", { share: shareText(issue) });
  const r = await sendShare(fetch, readToken(), issue);
  if (r.status === "sent") {
    clearPending(store);
    const entry = entryFromIssue(issue, r.number, new Date().toISOString());
    writeLog([entry, ...readLog()]);
    banner(`Sent ✓ #${r.number}. Filed under ${categoryLabel(entry.platform)}${typeLabel(entry.type) ? `, ${typeLabel(entry.type)}` : ""}.`, { tone: "ok", share: shareText(issue) });
    render();
    setTimeout(loadList, 6000);
    return true;
  }
  if (r.status === "auth") { writeToken(""); showToken("GitHub refused the token. Paste a new one; your share is kept."); banner(null); return false; }
  if (r.status === "error") { clearPending(store); banner(`${r.reason} Not sent.`, { tone: "err", share: shareText(issue) }); return false; }
  banner(`${r.reason} Your share is kept.`, { tone: "err", share: shareText(issue), retry: true });
  return false;
}

async function init() {
  await takeSharedFiles();
  const params = new URLSearchParams(location.search);
  const shared = buildIssue({ title: params.get("title"), text: params.get("text"), url: params.get("url") }, "android");
  if (shared) savePending(store, shared);
  // Drop the share from the address, so a reload or a restore from recents can't post it twice.
  history.replaceState(null, "", "/");

  $("token-form").addEventListener("submit", (e) => {
    e.preventDefault();
    writeToken($("token-input").value.trim());
    $("token-input").value = "";
    showMain();
    const pending = loadPending(store);
    if (pending) send(pending);
    if (queued.length) sendFiles();
    loadList();
  });
  $("composer").addEventListener("submit", async (e) => {
    e.preventDefault();
    const issue = buildIssue({ text: $("paste").value }, "android");
    if (issue && (await send(issue))) $("paste").value = "";
  });
  $("retry-button").addEventListener("click", () => { if (queued.length) return sendFiles(); const p = loadPending(store); if (p) send(p); });
  $("files").addEventListener("change", (e) => {
    for (const f of e.target.files) queued.push(prepareFile(f));
    e.target.value = "";
    sendFiles();
  });
  $("refresh").addEventListener("click", loadList);
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") loadList(); });
  setInterval(render, 60_000);
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});

  if (!readToken()) return showToken();
  showMain();
  render();
  loadList();
  const pending = shared || loadPending(store);
  if (pending) send(pending);
  if (queued.length) sendFiles();
}

init();
