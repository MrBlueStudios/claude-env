import { test } from "node:test";
import assert from "node:assert/strict";
import { classify } from "./app.js";
import {
  splitKind, categoryLabel, categoryColor, typeLabel, statusOf, parseIssue, ago,
  groupShares, mergeLocal, entryFromIssue, fetchHistory,
} from "./history.js";

const NOW = Date.parse("2026-11-25T17:30:00Z");
const issue = (over = {}) => ({
  number: 5, title: "t", state: "open", labels: [{ name: "inbox" }], user: { login: "MrBlueStudios" },
  created_at: "2026-11-25T17:10:00Z", html_url: "https://github.com/MrBlueStudios/crew-vault/issues/5",
  body: "https://vm.tiktok.com/ZG/\n\nkind: tiktok-short-link\nurl: https://vm.tiktok.com/ZG/\nid: abc\nvia: android",
  ...over,
});

// --- new link types: pictures, videos and diagrams ----------------------------------------------
for (const [url, kind] of [
  ["https://example.com/pic.PNG?x=1", "image-file"],
  ["https://i.imgur.com/abc.jpg", "image-file"],
  ["https://example.com/clip.mp4", "video-file"],
  ["https://excalidraw.com/#json=abc", "diagram-excalidraw"],
  ["https://app.diagrams.net/#Habc", "diagram-diagrams"],
  ["https://www.figma.com/file/abc/x", "diagram-figma"],
  ["https://miro.com/app/board/abc/", "diagram-miro"],
]) test(`classify: ${url} → ${kind}`, () => assert.equal(classify(url), kind));

// --- names, colours, wording --------------------------------------------------------------------
test("splitKind: platform is everything before the first hyphen", () => {
  assert.deepEqual(splitKind("instagram-reel"), { platform: "instagram", type: "reel" });
  assert.deepEqual(splitKind("tiktok-short-link"), { platform: "tiktok", type: "short-link" });
  assert.deepEqual(splitKind("text"), { platform: "text", type: "" });
});
test("categoryLabel: the categories Léon named", () => {
  const labels = Object.fromEntries(["instagram", "tiktok", "douyin", "xiaohongshu", "youtube", "x", "reddit", "linkedin", "github", "web", "text", "image", "diagram", "video"].map((p) => [p, categoryLabel(p)]));
  assert.deepEqual(labels, {
    instagram: "Instagram", tiktok: "TikTok", douyin: "Douyin", xiaohongshu: "Xiaohongshu", youtube: "YouTube", x: "X",
    reddit: "Reddit", linkedin: "LinkedIn", github: "GitHub", web: "Websites", text: "Notes", image: "Pictures",
    diagram: "Diagrams", video: "Videos",
  });
  assert.equal(categoryLabel("naver"), "Naver");
});
test("categoryColor: stable per platform, different between platforms", () => {
  assert.equal(categoryColor("instagram"), categoryColor("instagram"));
  assert.notEqual(categoryColor("instagram"), categoryColor("tiktok"));
  assert.match(categoryColor("douyin"), /^hsl\(/);
});
test("typeLabel: plain words, and a shortlink says it hasn't been opened yet", () => {
  assert.equal(typeLabel("reel"), "Reel");
  assert.equal(typeLabel("short-link"), "Link, not opened yet");
  assert.equal(typeLabel(""), "");
  assert.equal(typeLabel("whatever"), "Whatever");
});

// --- status ---------------------------------------------------------------------------------------
test("statusOf: each label means one thing", () => {
  const k = (labels, state = "open") => statusOf(labels, state).key;
  assert.equal(k(["inbox"]), "waiting");
  assert.equal(k([]), "waiting");
  assert.equal(k(["retry"]), "retry");
  assert.equal(k(["needs-you"]), "needs-you");
  assert.equal(k(["todo"]), "todo");
  assert.equal(k(["skipped"], "closed"), "skipped");
  assert.equal(k(["unsafe"], "closed"), "unsafe");
  assert.equal(k(["expired"], "closed"), "expired");
  assert.equal(k([], "closed"), "done");
});
test("statusOf: the worst news wins when labels disagree", () => {
  assert.equal(statusOf(["todo", "unsafe"], "open").key, "unsafe");
});
test("statusOf: ignores the src: labels", () => {
  assert.equal(statusOf(["src:instagram", "inbox"], "open").key, "waiting");
});
test("statusOf: every status has words and a tone", () => {
  for (const l of [[], ["retry"], ["needs-you"], ["todo"], ["skipped"], ["unsafe"], ["expired"]]) {
    const s = statusOf(l, "open");
    assert.ok(s.label.length > 5 && ["info", "good", "warn", "bad", "muted"].includes(s.tone), JSON.stringify(s));
  }
});

// --- reading an issue -------------------------------------------------------------------------------
test("parseIssue: a new-format issue", () => {
  const e = parseIssue(issue());
  assert.equal(e.platform, "tiktok");
  assert.equal(e.type, "short-link");
  assert.equal(e.url, "https://vm.tiktok.com/ZG/");
  assert.equal(e.id, "abc");
  assert.equal(e.number, 5);
  assert.equal(e.status.key, "waiting");
  assert.equal(e.author, "MrBlueStudios");
});
test("parseIssue: an old-format issue is classified from its link", () => {
  const e = parseIssue(issue({ body: "https://www.instagram.com/p/Dgl9/\n\nvia: android", title: "x" }));
  assert.equal(e.platform, "instagram");
  assert.equal(e.type, "post");
  assert.equal(e.id, "#5");
});
test("parseIssue: a note with no link", () => {
  const e = parseIssue(issue({ body: "remember kokoro\n\nvia: laptop" }));
  assert.equal(e.platform, "text");
});
test("parseIssue: missing fields never throw", () => {
  assert.doesNotThrow(() => parseIssue({ number: 1, title: "t", labels: [], state: "open" }));
});

// --- time -----------------------------------------------------------------------------------------------
test("ago: from seconds to dates", () => {
  const at = (ms) => new Date(NOW - ms).toISOString();
  assert.equal(ago(at(10_000), NOW), "just now");
  assert.equal(ago(at(5 * 60_000), NOW), "5 min ago");
  assert.equal(ago(at(3 * 3_600_000), NOW), "3 h ago");
  assert.equal(ago(at(30 * 3_600_000), NOW), "yesterday");
  assert.equal(ago(at(4 * 86_400_000), NOW), "4 d ago");
  assert.match(ago(at(20 * 86_400_000), NOW), /^\d{1,2} \w{3}$/);
});
test("ago: a clock slightly ahead is still just now", () => {
  assert.equal(ago(new Date(NOW + 20_000).toISOString(), NOW), "just now");
});

// --- grouping -----------------------------------------------------------------------------------------
const share = (platform, at, id) => ({ id, platform, createdAt: at, title: id });
test("groupShares: one group per platform, newest group first, newest item first", () => {
  const groups = groupShares([
    share("instagram", "2026-11-25T10:00:00Z", "i1"),
    share("tiktok", "2026-11-25T12:00:00Z", "t1"),
    share("instagram", "2026-11-25T13:00:00Z", "i2"),
    share("web", "2026-11-24T09:00:00Z", "w1"),
  ]);
  assert.deepEqual(groups.map((g) => g.platform), ["instagram", "tiktok", "web"]);
  assert.deepEqual(groups[0].items.map((i) => i.id), ["i2", "i1"]);
  assert.equal(groups[0].label, "Instagram");
  assert.equal(groups[2].label, "Websites");
});
test("groupShares: empty in, empty out", () => assert.deepEqual(groupShares([]), []));

// --- this phone's own log, until GitHub's list catches up ----------------------------------------------
test("mergeLocal: a local entry GitHub doesn't list yet is kept, one it lists is dropped", () => {
  const remote = [{ id: "a", createdAt: "2026-11-25T10:00:00Z" }];
  const local = [{ id: "a", createdAt: "2026-11-25T10:00:01Z" }, { id: "b", createdAt: "2026-11-25T11:00:00Z" }];
  assert.deepEqual(mergeLocal(remote, local).map((e) => e.id), ["b", "a"]);
});
test("entryFromIssue: what the phone knows right after sending", () => {
  const e = entryFromIssue({ title: "t", body: "https://x.com/a/status/1\n\nkind: x-post\nurl: https://x.com/a/status/1\nid: z1\nvia: android" }, 9, "2026-11-25T17:10:00Z");
  assert.equal(e.platform, "x");
  assert.equal(e.number, 9);
  assert.equal(e.id, "z1");
  assert.equal(e.status.key, "syncing");
});

// --- loading the list -----------------------------------------------------------------------------------
test("fetchHistory: reads issues with no cache, drops pull requests, parses each", async () => {
  let seen;
  const fetchFn = async (url, init) => {
    seen = { url, init };
    return { status: 200, json: async () => [issue(), issue({ number: 6, pull_request: {} })] };
  };
  const r = await fetchHistory(fetchFn, "tok");
  assert.equal(r.status, "ok");
  assert.equal(r.shares.length, 1);
  assert.match(seen.url, /\/repos\/MrBlueStudios\/crew-vault\/issues\?state=all&per_page=100/);
  assert.equal(seen.init.cache, "no-store");
  assert.equal(seen.init.headers.Authorization, "Bearer tok");
});
test("fetchHistory: a token problem, a server problem and no network are told apart", async () => {
  const code = (status) => async () => ({ status, json: async () => ({}) });
  assert.equal((await fetchHistory(code(401), "t")).status, "auth");
  assert.equal((await fetchHistory(code(404), "t")).status, "auth");
  const bad = await fetchHistory(code(500), "t");
  assert.equal(bad.status, "error");
  assert.match(bad.reason, /GitHub's side/);
  const off = await fetchHistory(async () => { throw new TypeError("Failed to fetch"); }, "t");
  assert.equal(off.status, "error");
  assert.match(off.reason, /phone/);
});
