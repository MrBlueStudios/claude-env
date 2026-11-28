# Share inbox v0: rulings and deferred minors

The decisions Claude made on Léon's behalf while building the share inbox (plan
`2026-11-25-share-inbox-v0`), copied out of the build ledger before it was deleted on
2026-11-28. Each one says what it costs if it was wrong.

## Rulings

1. No worktree: claude-env and ~/Projects are jj-colocated, so work stacked on `@` without moving `main`. Cost if wrong: one `jj rebase`.
2. Another session was editing claude-env at the same time, so only this plan's paths were committed. Cost: none.
3. `.superpowers/` is in `.git/info/exclude` (local only), so the ledger never landed in a commit.
4. crew-memory gained no design.md change for inbox ideas; it lists no sources. Cost: none.
5. Creating the crew-vault repo waited for Léon's approval, since it is outward-facing.
6. The share-app tests run as `node --test share-app/*.test.mjs`, because Node 22 treats the directory as a module.
7. The page's DOM code lives in `app.js` behind `typeof document` (the CSP forbids inline scripts), plus a `style.css` the plan did not list.
8. The page checks the token before "nothing to send", so first-run token entry works.
9. Icons use `fc-match sans:bold` explicitly; ImageMagick has no default font here.
10. `/inbox` is user-invoked only (`disable-model-invocation: true`), so it costs no always-on context on four laptops.
11. Fetch recipes live in a sibling `fetch.md`; spec rules are copied in, because laptops may not have the spec checked out.
12. `just vet` needed a first-party `inbox` LICENSE exemption in `docs/vet-exemptions.md`. Cost: one line to withdraw.
13. The duplicate check strips tracking parameters (igsh, utm_*, si, and t and s on x.com and YouTube), because share links carry per-share ids.
14. `crew-vault/` is in `~/Projects/.git/info/exclude`, so the umbrella repo never snapshots the nested clone.
15. Review findings were re-graded to Important by effect and fixed: a pending share lost while making a token, re-send on reload, the retry screen showing the title, hand-written issues auto-closed, and an Ideas slug overwriting an existing note.
16. The page shows "Sent" instead of closing itself; `window.close()` is unreliable in an installed web app. Cost: one swipe back.
17. The acceptance test issue carried `via: laptop`; an L3 reel shows its fetch line only in the run table.
18. The 500 errors during the field test were GitHub's own API, not content: replaying all failing shares through the page's code sent 9 of 9.

## Deferred minors

- Multi-line text-only titles keep their newlines.
- The Instagram L4 comment says "attach the video", but no recipe downloads a private-repo attachment.
- `just share-deploy` also publishes `app.test.mjs` (harmless).
- Short links cannot be resolved in the browser (CORS), so `/inbox` resolves them. The Asian-platform recipes were measured for Weibo, Xiaohongshu, Douyin and LinkedIn on 2026-11-26; WeChat, Zhihu and Bilibili are still unmeasured (ct-inbox-asian-fetch).
- The page shows plain "Sending…" for up to about 15 seconds while it retries.
