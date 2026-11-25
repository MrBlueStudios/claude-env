// Crew inbox share target: turns an Android share into an issue on the crew-vault repo.
// Spec: claude-env docs/superpowers/specs/2026-11-25-share-inbox-design.md
export const REPO = "MrBlueStudios/crew-vault";
const TOKEN_KEY = "crewShareToken";

// ASCII-only on purpose: a link that runs into Chinese text or full-width punctuation ends there,
// and no quote, backtick, `$` or backslash survives into a link the /inbox skill puts in a shell.
export function extractUrl(text = "") {
  const m = /https?:\/\/[A-Za-z0-9\-._~:/?#\[\]@!&()*+,;=%]+/i.exec(text || "");
  if (!m) return null;
  let u = m[0];
  while (/[.,;:!?]$/.test(u) || (u.endsWith(")") && u.split(")").length > u.split("(").length)) u = u.slice(0, -1);
  try { new URL(u); } catch { return null; }
  return u;
}

// platform → hosts (a host also matches its subdomains), the shorteners among them, and a
// path → kind rule. A shortener's real kind is only known after it redirects, which a browser
// can't read, so /inbox resolves those. UNVERIFIED for the Asian platforms: classification only
// reads the link; how well each can be fetched logged out is /inbox's problem (fetch.md).
const PLATFORMS = [
  ["instagram", ["instagram.com", "instagr.am"], ["instagr.am"], (p) => /\/reels?\//.test(p) ? "reel" : /\/p\//.test(p) ? "post" : /\/stories\//.test(p) ? "story" : "page"],
  ["tiktok", ["tiktok.com"], ["vm.tiktok.com", "vt.tiktok.com"], (p) => /^\/t\//.test(p) ? "short-link" : /\/video\//.test(p) ? "video" : /\/photo\//.test(p) ? "slideshow" : "page"],
  ["youtube", ["youtube.com", "youtu.be"], [], (p, h) => /\/shorts\//.test(p) ? "short" : /^\/(@|channel\/|c\/)/.test(p) ? "channel" : /^\/playlist/.test(p) ? "playlist" : h === "youtu.be" || /^\/(watch|live|embed)/.test(p) ? "video" : "page"],
  ["x", ["x.com", "twitter.com", "t.co"], ["t.co"], (p) => /\/status\//.test(p) ? "post" : "profile"],
  ["reddit", ["reddit.com", "redd.it"], ["redd.it"], (p) => /\/comments\//.test(p) ? "post" : /^\/r\//.test(p) ? "subreddit" : "page"],
  ["github", ["github.com"], [], (p, h) => h.startsWith("gist.") ? "gist" : h !== "github.com" ? "page" : /\/issues\/\d+/.test(p) ? "issue" : /\/pull\/\d+/.test(p) ? "pull" : /^\/[^/]+\/[^/]+\/?$/.test(p) ? "repo" : "page"],
  ["linkedin", ["linkedin.com", "lnkd.in"], ["lnkd.in"], (p) => /^\/(posts|feed\/update)/.test(p) ? "post" : /^\/jobs\/view/.test(p) ? "job" : /^\/pulse\//.test(p) ? "article" : /^\/in\//.test(p) ? "profile" : /^\/company\//.test(p) ? "company" : "page"],
  ["substack", ["substack.com"], [], (p) => /^\/p\//.test(p) ? "article" : /^\/note\//.test(p) ? "note" : "page"],
  ["medium", ["medium.com"], [], (p) => p.split("/").filter(Boolean).length > 1 ? "article" : "page"],
  ["facebook", ["facebook.com", "fb.com", "fb.watch", "fb.me"], ["fb.watch", "fb.me"], (p) => /\/reel\//.test(p) ? "reel" : /\/(watch|videos)\b/.test(p) ? "video" : /\/posts\//.test(p) ? "post" : "page"],
  ["threads", ["threads.net", "threads.com"], [], (p) => /\/post\//.test(p) ? "post" : "page"],
  ["bluesky", ["bsky.app"], [], (p) => /\/post\//.test(p) ? "post" : "page"],
  ["pinterest", ["pinterest.com", "pin.it"], ["pin.it"], (p) => /^\/pin\//.test(p) ? "pin" : "page"],
  ["telegram", ["t.me"], [], (p) => /^\/[^/]+\/\d+/.test(p) ? "post" : "page"],
  ["twitch", ["twitch.tv"], [], (p) => /\/videos\//.test(p) ? "video" : /\/clip\//.test(p) ? "clip" : "page"],
  ["xiaohongshu", ["xiaohongshu.com", "xhslink.com"], ["xhslink.com"], (p) => /^\/(explore|discovery\/item)\//.test(p) ? "note" : /^\/user\/profile/.test(p) ? "profile" : "page"],
  ["douyin", ["douyin.com", "iesdouyin.com"], ["v.douyin.com"], (p) => /\/video\//.test(p) ? "video" : /\/note\//.test(p) ? "note" : "page"],
  ["bilibili", ["bilibili.com", "bilibili.tv", "b23.tv"], ["b23.tv"], (p, h) => /\/video\//.test(p) ? "video" : /\/read\//.test(p) ? "article" : h.startsWith("space.") ? "profile" : "page"],
  ["wechat", ["weixin.qq.com", "wechat.com"], [], (p, h) => h.startsWith("mp.") ? "article" : "page"],
  ["weibo", ["weibo.com", "weibo.cn", "t.cn"], ["t.cn"], (p) => /^\/(detail|status)\/|^\/\d+\/\w+/.test(p) ? "post" : "page"],
  ["zhihu", ["zhihu.com", "zhi.hu"], ["zhi.hu"], (p, h) => /\/answer\//.test(p) ? "answer" : /\/question\//.test(p) ? "question" : h.startsWith("zhuanlan.") || /^\/p\//.test(p) ? "article" : "page"],
  ["diagram", ["excalidraw.com", "draw.io", "diagrams.net", "figma.com", "miro.com", "lucid.app", "lucidchart.com", "mermaid.live", "whimsical.com", "tldraw.com"], [], (p, h) => h.split(".").slice(-2, -1)[0]],
  ["douban", ["douban.com"], [], () => "page"],
  ["toutiao", ["toutiao.com"], [], () => "page"],
  ["kuaishou", ["kuaishou.com", "kwai.com"], ["v.kuaishou.com"], (p) => /\/short-video\//.test(p) ? "video" : "page"],
  ["line", ["line.me", "lin.ee"], ["lin.ee"], () => "page"],
  ["kakao", ["kakao.com", "kko.to"], ["kko.to"], (p, h) => h.startsWith("tv.") ? "video" : h.startsWith("story.") ? "post" : "page"],
  ["naver", ["naver.com", "naver.me"], ["naver.me"], (p, h) => /^(m\.)?blog\./.test(h) ? "article" : h.startsWith("cafe.") ? "post" : h.startsWith("tv.") ? "video" : "page"],
];

export function classify(link) {
  let u;
  try { u = new URL(link); } catch { return "text"; }
  const host = u.hostname.toLowerCase().replace(/^(www|m|mobile)\./, "");
  const ext = /\.([a-z0-9]{2,5})$/i.exec(u.pathname)?.[1]?.toLowerCase();
  if (["png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "bmp"].includes(ext)) return "image-file";
  if (["mp4", "mov", "webm", "m4v", "mkv"].includes(ext)) return "video-file";
  for (const [name, hosts, shorts, kindOf] of PLATFORMS) {
    if (!hosts.some((d) => host === d || host.endsWith(`.${d}`))) continue;
    return `${name}-${shorts.includes(host) ? "short-link" : kindOf(u.pathname, host)}`;
  }
  return "web-page";
}

const oneLine = (s) => s.replace(/\s+/g, " ").trim();
const cut = (s, n) => Array.from(s).slice(0, n).join("");

export function buildIssue({ title = "", text = "", url = "" } = {}, via, id = crypto.randomUUID()) {
  [title, text, url] = [title, text, url].map((s) => (s || "").trim());
  if (!title && !text && !url) return null;
  const link = url || extractUrl(text);
  const parts = [text, url && !text.includes(url) ? url : ""].filter(Boolean);
  const meta = [`kind: ${link ? classify(link) : "text"}`, link && `url: ${link}`, `id: ${id}`, `via: ${via}`];
  return {
    title: cut(oneLine(title || url || text), 120),
    body: `${(parts.length ? parts : [title]).join("\n")}\n\n${meta.filter(Boolean).join("\n")}`,
    labels: ["inbox"],
  };
}

// What each answer means, in words for the person holding the phone.
export function explain(code) {
  const saved = " The share may already be saved, so check before sending it again.";
  const says = {
    network: "This phone couldn't reach GitHub: no signal, airplane mode, a Wi-Fi sign-in page, or the connection dropped.",
    401: "401: GitHub doesn't accept this token (mistyped, revoked or expired).",
    403: "403: GitHub blocked the request (the token lacks permission, or too much was sent too fast).",
    404: "404: GitHub says this token can't see the crew-vault repo (wrong repository chosen when the token was made).",
    422: "422: GitHub rejected the content of this share.",
    429: "429: GitHub says too many requests; wait a minute.",
  };
  if (says[code]) return says[code];
  if (code >= 500) return `${code}: an error on GitHub's side, not on your phone or in this page.${saved}`;
  return `${code}: GitHub gave an answer this page doesn't know.`;
}

const headers = (token) => ({ Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json" });

export async function postIssue(fetchFn, token, issue) {
  let res;
  try {
    res = await fetchFn(`https://api.github.com/repos/${REPO}/issues`, {
      method: "POST",
      headers: { ...headers(token), "Content-Type": "application/json" },
      body: JSON.stringify(issue),
    });
  } catch (err) {
    return { status: "retry", reason: `${explain("network")} (${err.message})` };
  }
  if (res.status === 201) return { status: "sent", number: (await res.json()).number };
  // The repo is fixed, so 404 means this token can't see it: a token problem, not a missing page.
  if ([401, 403, 404].includes(res.status)) return { status: "auth" };
  if (res.status === 429 || res.status >= 500) return { status: "retry", reason: explain(res.status) };
  return { status: "error", reason: explain(res.status) };
}

// GitHub sometimes saves an issue and still answers 500 (it did for lipsum.com: #2, then a
// Retry made #3), so after any failed try, look for this share's own id among the latest issues.
// Two traps, both measured: the list lags 4–5 seconds behind a fresh issue (measured), and GitHub marks
// it max-age=60, so a cached copy would hide the share for a minute.
async function findExisting(fetchFn, token, id) {
  try {
    const res = await fetchFn(`https://api.github.com/repos/${REPO}/issues?state=all&per_page=15&sort=created&direction=desc`, { headers: headers(token), cache: "no-store" });
    if (res.status !== 200) return null;
    return (await res.json()).find((i) => (i.body || "").includes(`id: ${id}`))?.number ?? null;
  } catch { return null; }
}

const LOOKUP_DELAY_MS = [6000, 6000]; // measured: a new issue shows in the list after 3.6–4.6 s
export async function sendShare(fetchFn, token, issue, sleep = (ms) => new Promise((r) => setTimeout(r, ms))) {
  const id = /^id: (\S+)$/m.exec(issue.body)?.[1];
  let r;
  for (const delay of LOOKUP_DELAY_MS) {
    r = await postIssue(fetchFn, token, issue);
    if (r.status !== "retry") return r;
    await sleep(delay);
    const number = id && (await findExisting(fetchFn, token, id));
    if (number) return { status: "sent", number };
  }
  return r;
}

// The unsent share is kept in storage, so leaving the app to make a new token loses nothing.
const PENDING_KEY = "crewSharePending";
export function savePending(storage, issue) {
  try { storage.setItem(PENDING_KEY, JSON.stringify(issue)); } catch {}
}
export function loadPending(storage) {
  try { return JSON.parse(storage.getItem(PENDING_KEY)) || null; } catch { return null; }
}
export function clearPending(storage) {
  try { storage.removeItem(PENDING_KEY); } catch {}
}

// Storage can throw (private mode, blocked site data); the share must survive that.
export function readToken() {
  try { return localStorage.getItem(TOKEN_KEY) || ""; } catch { return ""; }
}
export function writeToken(value) {
  try { value ? localStorage.setItem(TOKEN_KEY, value) : localStorage.removeItem(TOKEN_KEY); } catch {}
}
