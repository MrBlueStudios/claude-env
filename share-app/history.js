// What was shared, in which category, when, and how far it got. Pure functions: ui.js draws them.
import { REPO, classify, extractUrl, explain } from "./app.js";

const LABELS = {
  web: "Websites", text: "Notes", image: "Pictures", diagram: "Diagrams", video: "Videos",
  x: "X", github: "GitHub", youtube: "YouTube", tiktok: "TikTok", linkedin: "LinkedIn",
  wechat: "WeChat", xiaohongshu: "RedNote", bilibili: "Bilibili", kakao: "Kakao",
};
const TYPES = { "short-link": "Link, not opened yet", file: "File" };

export function splitKind(kind) {
  const i = kind.indexOf("-");
  return i < 0 ? { platform: kind, type: "" } : { platform: kind.slice(0, i), type: kind.slice(i + 1) };
}
export const categoryLabel = (p) => LABELS[p] || p.charAt(0).toUpperCase() + p.slice(1);
export function categoryColor(p) {
  let h = 0;
  for (const c of p) h = (h * 31 + c.charCodeAt(0)) % 360;
  return `hsl(${h} 65% 58%)`;
}
export const typeLabel = (t) => TYPES[t] ?? (t ? t.charAt(0).toUpperCase() + t.slice(1) : "");

// First match wins, worst news first. Only the labels /inbox sets matter; src:* is ignored.
export function statusOf(labels, state) {
  const has = (l) => labels.includes(l);
  if (has("unsafe")) return { key: "unsafe", label: "Flagged unsafe", tone: "bad" };
  if (has("todo")) return { key: "todo", label: "Filed · idea saved", tone: "good" };
  if (has("skipped")) return { key: "skipped", label: "Judged: not worth it", tone: "muted" };
  if (has("expired")) return { key: "expired", label: "Expired, no reply", tone: "muted" };
  if (has("needs-you")) return { key: "needs-you", label: "Needs you: paste the caption", tone: "warn" };
  if (has("retry")) return { key: "retry", label: "Claude is retrying the fetch", tone: "warn" };
  if (state === "closed") return { key: "done", label: "Done", tone: "muted" };
  return { key: "waiting", label: "Sent · waiting for Claude", tone: "info" };
}

export function parseIssue(i) {
  const body = i.body || "";
  const kind = /^kind: (\S+)$/m.exec(body)?.[1];
  const url = /^url: (.+)$/m.exec(body)?.[1]?.trim() || extractUrl(body);
  const { platform, type } = splitKind(kind || (url ? classify(url) : "text"));
  return {
    id: /^id: (\S+)$/m.exec(body)?.[1] ?? `#${i.number}`,
    number: i.number,
    title: i.title,
    url,
    platform,
    type,
    status: statusOf((i.labels || []).map((l) => l.name ?? l), i.state),
    createdAt: i.created_at,
    author: i.user?.login ?? null,
    href: i.html_url,
  };
}

export function ago(iso, now = Date.now()) {
  const s = Math.max(0, (now - Date.parse(iso)) / 1000);
  if (s < 45) return "just now";
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 172800) return "yesterday";
  if (s < 604800) return `${Math.floor(s / 86400)} d ago`;
  return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short" }).replace(/^(\d+) (\w{3}).*$/, "$1 $2");
}

export function groupShares(shares) {
  const by = new Map();
  for (const s of [...shares].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))) {
    if (!by.has(s.platform)) by.set(s.platform, { platform: s.platform, label: categoryLabel(s.platform), color: categoryColor(s.platform), items: [] });
    by.get(s.platform).items.push(s);
  }
  return [...by.values()];
}

// GitHub's list lags 4-5 s behind a new issue, so this phone keeps what it just sent.
export function mergeLocal(remote, local) {
  const known = new Set(remote.map((e) => e.id));
  return [...remote, ...local.filter((e) => !known.has(e.id))].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
}
export function entryFromIssue(issue, number, createdAt) {
  const e = parseIssue({ number, title: issue.title, body: issue.body, labels: issue.labels, state: "open", created_at: createdAt });
  return { ...e, status: { key: "syncing", label: "Sent · syncing…", tone: "info" } };
}

export async function fetchHistory(fetchFn, token) {
  let res;
  try {
    res = await fetchFn(`https://api.github.com/repos/${REPO}/issues?state=all&per_page=100&sort=created&direction=desc`, {
      headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json" },
      cache: "no-store",
    });
  } catch (err) {
    return { status: "error", reason: `${explain("network")} (${err.message})` };
  }
  if ([401, 403, 404].includes(res.status)) return { status: "auth" };
  if (res.status !== 200) return { status: "error", reason: explain(res.status) };
  return { status: "ok", shares: (await res.json()).filter((i) => !i.pull_request).map(parseIssue) };
}
