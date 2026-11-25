import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildIssue, postIssue, sendShare, extractUrl, classify, explain,
  REPO, savePending, loadPending, clearPending,
} from "./app.js";

test("buildIssue: Instagram share", () => {
  const url = "https://www.instagram.com/reel/ABC/?igsh=x";
  const issue = buildIssue({ text: url }, "android");
  assert.equal(issue.title, url);
  assert.ok(issue.body.endsWith("\nvia: android"));
  assert.match(issue.body, /^kind: instagram-reel$/m);
  assert.match(issue.body, /^id: \S+$/m);
  assert.deepEqual(issue.labels, ["inbox"]);
});

test("buildIssue: Chrome share", () => {
  const issue = buildIssue({ title: "Some repo", url: "https://github.com/a/b", text: "" }, "android");
  assert.equal(issue.title, "Some repo");
  const sharePart = issue.body.split("\n\nkind:")[0];
  assert.equal(sharePart.split("https://github.com/a/b").length - 1, 1);
  assert.match(issue.body, /^url: https:\/\/github.com\/a\/b$/m);
});

test("buildIssue: URL repeated in text", () => {
  const url = "https://x.com/a/status/1";
  const issue = buildIssue({ text: `look ${url}`, url }, "android");
  assert.equal(issue.body.split("\n\nkind:")[0].split(url).length - 1, 1);
});

test("buildIssue: text-only share", () => {
  const issue = buildIssue({ text: "remember to look at kokoro" }, "android");
  assert.notEqual(issue, null);
  assert.equal(issue.title, "remember to look at kokoro");
});

test("buildIssue: empty share", () => {
  assert.equal(buildIssue({}, "android"), null);
  assert.equal(buildIssue({ title: "  ", text: "", url: "" }, "android"), null);
});

test("buildIssue: long text", () => {
  const issue = buildIssue({ text: "a".repeat(500) }, "android");
  assert.ok(issue.title.length <= 120);
});

const ISSUE = { title: "t", body: "b", labels: ["inbox"] };

test("postIssue: 201 → sent", async () => {
  let call;
  const fakeFetch = async (url, init) => {
    call = { url, init };
    return { status: 201, json: async () => ({ number: 7 }) };
  };
  const result = await postIssue(fakeFetch, "tok", ISSUE);
  assert.deepEqual(result, { status: "sent", number: 7 });
  assert.equal(call.url, `https://api.github.com/repos/${REPO}/issues`);
  assert.equal(REPO, "MrBlueStudios/crew-vault");
  assert.equal(call.init.method, "POST");
  assert.equal(call.init.headers.Authorization, "Bearer tok");
  assert.equal(call.init.headers.Accept, "application/vnd.github+json");
  assert.deepEqual(JSON.parse(call.init.body), ISSUE);
});

for (const status of [401, 403]) {
  test(`postIssue: ${status} → auth`, async () => {
    const result = await postIssue(async () => ({ status, json: async () => ({}) }), "bad", ISSUE);
    assert.deepEqual(result, { status: "auth" });
  });
}

test("postIssue: network error → retry", async () => {
  const result = await postIssue(async () => { throw new TypeError("Failed to fetch"); }, "tok", ISSUE);
  assert.equal(result.status, "retry");
});

test("postIssue: 500 → retry", async () => {
  const result = await postIssue(async () => ({ status: 500, json: async () => ({}) }), "tok", ISSUE);
  assert.equal(result.status, "retry");
});

test("postIssue: 404 → auth (token can't see the repo)", async () => {
  const result = await postIssue(async () => ({ status: 404, json: async () => ({}) }), "tok", ISSUE);
  assert.deepEqual(result, { status: "auth" });
});

test("postIssue: 422 → error, not an endless retry", async () => {
  const result = await postIssue(async () => ({ status: 422, json: async () => ({}) }), "tok", ISSUE);
  assert.equal(result.status, "error");
});

test("postIssue: 429 → retry", async () => {
  const result = await postIssue(async () => ({ status: 429, json: async () => ({}) }), "tok", ISSUE);
  assert.equal(result.status, "retry");
});

function memoryStorage() {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k) };
}
const brokenStorage = { getItem() { throw new Error("blocked"); }, setItem() { throw new Error("blocked"); }, removeItem() { throw new Error("blocked"); } };

test("pending: a share survives until it is cleared", () => {
  const st = memoryStorage();
  savePending(st, ISSUE);
  assert.deepEqual(loadPending(st), ISSUE);
  clearPending(st);
  assert.equal(loadPending(st), null);
});

test("pending: blocked storage never throws", () => {
  assert.doesNotThrow(() => savePending(brokenStorage, ISSUE));
  assert.equal(loadPending(brokenStorage), null);
  assert.doesNotThrow(() => clearPending(brokenStorage));
});

// --- link extraction from messy share text ---------------------------------------------------

test("extractUrl: bare shortlink", () => {
  assert.equal(extractUrl("https://vm.tiktok.com/ZGdXo8b6A/"), "https://vm.tiktok.com/ZGdXo8b6A/");
});
test("extractUrl: Xiaohongshu text stops at the full-width comma", () => {
  const t = "64 【测试标题 - 用户 | 小红书】 😆 abc 😆 http://xhslink.com/a/AbCdEf，复制本条信息，打开【小红书】App查看精彩内容！";
  assert.equal(extractUrl(t), "http://xhslink.com/a/AbCdEf");
});
test("extractUrl: Douyin text", () => {
  const t = "7.99 复制打开抖音，看看【某人的作品】测试 # 标签 https://v.douyin.com/AbCdEf/ 12/12 abc:/ 😎";
  assert.equal(extractUrl(t), "https://v.douyin.com/AbCdEf/");
});
test("extractUrl: Chinese glued straight onto the link", () => {
  assert.equal(extractUrl("https://v.douyin.com/abc/复制此链接"), "https://v.douyin.com/abc/");
});
test("extractUrl: trailing sentence punctuation is dropped", () => {
  assert.equal(extractUrl("see https://example.com/a."), "https://example.com/a");
});
test("extractUrl: balanced parenthesis kept, wrapping one dropped", () => {
  assert.equal(extractUrl("(https://en.wikipedia.org/wiki/Foo_(bar))"), "https://en.wikipedia.org/wiki/Foo_(bar)");
});
test("extractUrl: a quote or $ ends the link, so no shell metacharacter survives", () => {
  assert.equal(extractUrl("https://a.com/x'$(id)"), "https://a.com/x");
});
test("extractUrl: no link", () => {
  assert.equal(extractUrl("remember to look at kokoro"), null);
  assert.equal(extractUrl(""), null);
});

// --- platform and content-type labels --------------------------------------------------------

const KINDS = [
  ["https://www.instagram.com/reel/DglJrFhh9Pq/?bqrl=x", "instagram-reel"],
  ["https://www.instagram.com/p/Dgl9_t_JTKd/?hvrq=x", "instagram-post"],
  ["https://www.instagram.com/share/reel/BAbc/", "instagram-reel"],
  ["https://www.instagram.com/stories/foo/123/", "instagram-story"],
  ["https://vm.tiktok.com/ZGdXo8b6A/", "tiktok-short-link"],
  ["https://www.tiktok.com/@a/video/1?is_from_webapp=1&sender_device=pc", "tiktok-video"],
  ["https://www.tiktok.com/@a/photo/1", "tiktok-slideshow"],
  ["https://youtu.be/abc", "youtube-video"],
  ["https://www.youtube.com/shorts/abc", "youtube-short"],
  ["https://x.com/a/status/1", "x-post"],
  ["https://t.co/abc", "x-short-link"],
  ["https://www.reddit.com/r/a/comments/1/x/", "reddit-post"],
  ["https://redd.it/abc", "reddit-short-link"],
  ["https://github.com/a/b", "github-repo"],
  ["https://github.com/a/b/issues/3", "github-issue"],
  ["https://docs.github.com/en/actions", "github-page"],
  ["https://www.linkedin.com/posts/a_x-activity-1-abc", "linkedin-post"],
  ["https://www.linkedin.com/jobs/view/123", "linkedin-job"],
  ["https://lnkd.in/abc", "linkedin-short-link"],
  ["https://someone.substack.com/p/title", "substack-article"],
  ["http://xhslink.com/a/AbCdEf", "xiaohongshu-short-link"],
  ["https://www.xiaohongshu.com/explore/65abc", "xiaohongshu-note"],
  ["https://v.douyin.com/AbCdEf/", "douyin-short-link"],
  ["https://www.douyin.com/video/123", "douyin-video"],
  ["https://www.bilibili.com/video/BV1xx", "bilibili-video"],
  ["https://b23.tv/abc", "bilibili-short-link"],
  ["https://mp.weixin.qq.com/s/abc", "wechat-article"],
  ["https://m.weibo.cn/detail/123", "weibo-post"],
  ["https://t.cn/abc", "weibo-short-link"],
  ["https://zhuanlan.zhihu.com/p/123", "zhihu-article"],
  ["https://www.zhihu.com/question/1/answer/2", "zhihu-answer"],
  ["https://lin.ee/abc", "line-short-link"],
  ["https://kko.to/abc", "kakao-short-link"],
  ["https://naver.me/abc", "naver-short-link"],
  ["https://blog.naver.com/a/123", "naver-article"],
  ["https://blitsol.com/", "web-page"],
  ["https://www.lipsum.com/", "web-page"],
  ["not a url", "text"],
  ["", "text"],
];
for (const [url, kind] of KINDS) {
  test(`classify: ${url || "(empty)"} → ${kind}`, () => assert.equal(classify(url), kind));
}

test("buildIssue: Xiaohongshu share carries kind, a clean url line, and the full caption", () => {
  const text = "64 【测试标题 - 用户 | 小红书】 😆 http://xhslink.com/a/AbCdEf，复制本条信息，打开【小红书】App查看";
  const issue = buildIssue({ text }, "android", "id1");
  assert.match(issue.body, /^kind: xiaohongshu-short-link$/m);
  assert.match(issue.body, /^url: http:\/\/xhslink\.com\/a\/AbCdEf$/m);
  assert.ok(issue.body.includes("测试标题"));
  assert.equal(issue.title, text.replace(/\s+/g, " "));
});

test("buildIssue: a text-only share has kind text and no url line", () => {
  const issue = buildIssue({ text: "remember to look at kokoro" }, "android", "id1");
  assert.match(issue.body, /^kind: text$/m);
  assert.doesNotMatch(issue.body, /^url: /m);
});

test("buildIssue: a title-only share keeps the title in the body", () => {
  const issue = buildIssue({ title: "Just a title" }, "android", "id1");
  assert.ok(issue.body.startsWith("Just a title"));
});

test("buildIssue: the title is cut on a code point, never inside an emoji", () => {
  const issue = buildIssue({ text: "x".repeat(119) + "😀 tail" }, "android", "id1");
  assert.ok(issue.title.isWellFormed());
  assert.ok(JSON.stringify(issue).includes("\\ud83d") === false);
});

test("buildIssue: newlines in a shared title collapse to spaces", () => {
  assert.equal(buildIssue({ title: "a\nb\n\nc" }, "android", "id1").title, "a b c");
});

test("buildIssue: every call gets its own id unless one is passed", () => {
  const a = buildIssue({ text: "a" }, "android").body.match(/^id: (\S+)$/m)[1];
  const b = buildIssue({ text: "a" }, "android").body.match(/^id: (\S+)$/m)[1];
  assert.notEqual(a, b);
});

// --- plain-English errors --------------------------------------------------------------------

test("explain: 500 says it is GitHub's side and that the share may be saved", () => {
  const msg = explain(500);
  assert.match(msg, /500/);
  assert.match(msg, /GitHub's side/);
  assert.match(msg, /may already be saved/);
});
test("explain: network says phone, not GitHub", () => assert.match(explain("network"), /phone/));
test("explain: every code the page can show has a sentence", () => {
  for (const c of [401, 403, 404, 422, 429, 500, 502, 503, "network", 418]) assert.ok(explain(c).length > 20, String(c));
});
test("postIssue: the retry reason is the plain-English one", async () => {
  const r = await postIssue(async () => ({ status: 500, json: async () => ({}) }), "tok", ISSUE);
  assert.match(r.reason, /GitHub's side/);
});

// --- sendShare: look before retrying, so a lost answer never makes a duplicate ----------------

const SHARE = { title: "t", body: "x\n\nkind: web-page\nid: abc\nvia: android", labels: ["inbox"] };

function fakeGitHub({ post, list }) {
  const log = { posts: 0, lists: 0, events: [], listInits: [] };
  const fetchFn = async (url, init = {}) => {
    if (init.method === "POST") {
      log.posts += 1;
      log.events.push("post");
      const r = post(log.posts);
      if (r instanceof Error) throw r;
      return { status: r.status, json: async () => r.body ?? {} };
    }
    log.lists += 1;
    log.events.push("list");
    log.listInits.push(init);
    const r = list(log.lists);
    return { status: r.status, json: async () => r.body ?? [] };
  };
  return { fetchFn, log };
}
const noSleep = (log) => { const waits = []; const fn = async (ms) => { waits.push(ms); log?.events.push("wait"); }; fn.waits = waits; return fn; };

test("sendShare: a 500 for a share GitHub did save is found, not posted twice", async () => {
  const { fetchFn, log } = fakeGitHub({
    post: () => ({ status: 500 }),
    list: () => ({ status: 200, body: [{ number: 2, body: "x\nid: abc\nvia: android" }] }),
  });
  assert.deepEqual(await sendShare(fetchFn, "tok", SHARE, noSleep()), { status: "sent", number: 2 });
  assert.equal(log.posts, 1);
});

test("sendShare: a 500 for a share GitHub did not save is retried and sent", async () => {
  const sleep = noSleep();
  const { fetchFn, log } = fakeGitHub({
    post: (n) => (n === 1 ? { status: 500 } : { status: 201, body: { number: 9 } }),
    list: () => ({ status: 200, body: [{ number: 1, body: "someone else's\nid: zzz" }] }),
  });
  assert.deepEqual(await sendShare(fetchFn, "tok", SHARE, sleep), { status: "sent", number: 9 });
  assert.equal(log.posts, 2);
  assert.deepEqual(sleep.waits, [6000]);
});

test("sendShare: two failures in a row end as retry, each after a wait for the list", async () => {
  const sleep = noSleep();
  const { fetchFn, log } = fakeGitHub({ post: () => ({ status: 503 }), list: () => ({ status: 200, body: [] }) });
  const r = await sendShare(fetchFn, "tok", SHARE, sleep);
  assert.equal(r.status, "retry");
  assert.equal(log.posts, 2);
  assert.deepEqual(sleep.waits, [6000, 6000]);
});

test("sendShare: it waits for GitHub's list to catch up before looking, and looks after the last try too", async () => {
  const { fetchFn, log } = fakeGitHub({ post: () => ({ status: 500 }), list: () => ({ status: 200, body: [] }) });
  await sendShare(fetchFn, "tok", SHARE, noSleep(log));
  assert.deepEqual(log.events, ["post", "wait", "list", "post", "wait", "list"]);
});

test("sendShare: the lookup never accepts a cached list (GitHub marks it max-age=60)", async () => {
  const { fetchFn, log } = fakeGitHub({ post: () => ({ status: 500 }), list: () => ({ status: 200, body: [] }) });
  await sendShare(fetchFn, "tok", SHARE, noSleep());
  assert.ok(log.listInits.length > 0);
  assert.ok(log.listInits.every((i) => i.cache === "no-store"));
});

test("sendShare: a dropped connection is retried the same way", async () => {
  const { fetchFn, log } = fakeGitHub({ post: () => new TypeError("Failed to fetch"), list: () => ({ status: 200, body: [] }) });
  const r = await sendShare(fetchFn, "tok", SHARE, noSleep());
  assert.equal(r.status, "retry");
  assert.equal(log.posts, 2);
});

test("sendShare: a lookup that itself fails does not stop the retry", async () => {
  const { fetchFn } = fakeGitHub({
    post: (n) => (n === 1 ? { status: 500 } : { status: 201, body: { number: 4 } }),
    list: () => ({ status: 500 }),
  });
  assert.deepEqual(await sendShare(fetchFn, "tok", SHARE, noSleep()), { status: "sent", number: 4 });
});

test("sendShare: a token problem or a refused share stops at once", async () => {
  for (const [code, status] of [[401, "auth"], [404, "auth"], [422, "error"]]) {
    const { fetchFn, log } = fakeGitHub({ post: () => ({ status: code }), list: () => ({ status: 200, body: [] }) });
    assert.equal((await sendShare(fetchFn, "tok", SHARE, noSleep())).status, status);
    assert.equal(log.posts, 1);
    assert.equal(log.lists, 0);
  }
});
