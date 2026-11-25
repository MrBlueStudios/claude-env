// Crew inbox share target: turns an Android share into an issue on the crew-vault repo.
// Spec: claude-env docs/superpowers/specs/2026-11-25-share-inbox-design.md
export const REPO = "MrBlueStudios/crew-vault";
const TOKEN_KEY = "crewShareToken";

export function buildIssue({ title = "", text = "", url = "" } = {}, via) {
  [title, text, url] = [title, text, url].map((s) => (s || "").trim());
  if (!title && !text && !url) return null;
  const parts = [text, url && !text.includes(url) ? url : ""].filter(Boolean);
  return {
    title: (title || url || text).slice(0, 120),
    body: `${parts.join("\n")}\n\nvia: ${via}`,
    labels: ["inbox"],
  };
}

export async function postIssue(fetchFn, token, issue) {
  let res;
  try {
    res = await fetchFn(`https://api.github.com/repos/${REPO}/issues`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(issue),
    });
  } catch (err) {
    return { status: "retry", reason: `Couldn't reach GitHub (${err.message}).` };
  }
  if (res.status === 201) return { status: "sent", number: (await res.json()).number };
  // The repo is fixed, so 404 means this token can't see it: a token problem, not a missing page.
  if ([401, 403, 404].includes(res.status)) return { status: "auth" };
  if (res.status === 429 || res.status >= 500) return { status: "retry", reason: `GitHub answered ${res.status}.` };
  return { status: "error", reason: `GitHub refused this share (${res.status}).` };
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
function readToken() {
  try { return localStorage.getItem(TOKEN_KEY) || ""; } catch { return ""; }
}
function writeToken(value) {
  try { value ? localStorage.setItem(TOKEN_KEY, value) : localStorage.removeItem(TOKEN_KEY); } catch {}
}

function init() {
  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const shared = buildIssue(
    { title: params.get("title"), text: params.get("text"), url: params.get("url") },
    "android",
  );
  if (shared) savePending(window.localStorage, shared);
  // Drop the share from the address, so a reload or a restore from recents can't post it twice.
  history.replaceState(null, "", "/");
  const issue = shared || loadPending(window.localStorage);
  const show = (id) => ["token", "result", "retry"].forEach((s) => ($(s).hidden = s !== id));
  const say = (msg) => { $("result-text").textContent = msg; show("result"); };

  async function send() {
    const token = readToken();
    if (!token) return show("token");
    if (!issue) return say("Ready. Share a link or some text to Crew inbox.");
    $("result-text").textContent = "Sending…";
    show("result");
    const r = await postIssue(fetch, token, issue);
    if (r.status === "sent") {
      clearPending(window.localStorage);
      return say(`Sent to the crew inbox (#${r.number}).`);
    }
    if (r.status === "error") {
      clearPending(window.localStorage);
      return say(`${r.reason} Not sent: ${issue.body.replace(/\n\nvia: .*$/, "")}`);
    }
    if (r.status === "auth") {
      writeToken("");
      $("token-why").textContent = "GitHub refused the token. Paste a new one; your share is kept.";
      return show("token");
    }
    $("retry-text").textContent = `${r.reason} Your share is kept:`;
    $("retry-share").textContent = issue.body.replace(/\n\nvia: .*$/, "");
    show("retry");
  }

  $("token-form").addEventListener("submit", (e) => {
    e.preventDefault();
    writeToken($("token-input").value.trim());
    $("token-input").value = "";
    send();
  });
  $("retry-button").addEventListener("click", send);
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
  send();
}

if (typeof document !== "undefined") init();
