import { test } from "node:test";
import assert from "node:assert/strict";
import { buildIssue, postIssue, REPO, savePending, loadPending, clearPending } from "./app.js";

test("buildIssue: Instagram share", () => {
  const url = "https://www.instagram.com/reel/ABC/?igsh=x";
  const issue = buildIssue({ text: url }, "android");
  assert.equal(issue.title, url);
  assert.ok(issue.body.endsWith("\n\nvia: android"));
  assert.deepEqual(issue.labels, ["inbox"]);
});

test("buildIssue: Chrome share", () => {
  const issue = buildIssue({ title: "Some repo", url: "https://github.com/a/b", text: "" }, "android");
  assert.equal(issue.title, "Some repo");
  assert.equal(issue.body.split("https://github.com/a/b").length - 1, 1);
});

test("buildIssue: URL repeated in text", () => {
  const url = "https://x.com/a/status/1";
  const issue = buildIssue({ text: `look ${url}`, url }, "android");
  assert.equal(issue.body.split(url).length - 1, 1);
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
