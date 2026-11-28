---
name: legal-audit
description: Use when asked whether a project or website is legal, for a compliance or GDPR audit, a cookie banner or privacy policy check, whether something could get him sued, AI Act or accessibility obligations, or what a lawyer still needs to look at
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill
---

<!-- Léon's own skill, written for this repo's crew: copied from Claude_testing (claude-lab) skills/legal-audit on 2026-11-28. -->

Legal audit of $ARGUMENTS. Background: `docs/research/legal-compliance.md`.

## 0. You are not giving legal advice, and the report must say so

This skill produces **a list of checks that passed, a list that failed, and a list only a lawyer
can answer.** It never produces a verdict. "Compliant", "you are fine", "no legal risk" and
"this will not get you sued" are all forbidden outputs — the research behind this skill is
secondary law-firm commentary, not primary law, and several of its most relevant dates are
disputed between sources.

Every report opens with one line: what it checked, on what date, and that it is not legal advice.

## 1. Check what is visible first, because that is what gets reported

Enforcement arrives by complaint, not by audit. Nobody inspects a one-person studio; a user
notices a dead "reject" button or an ignored deletion request and files. So the order is: what a
stranger can see, then what a customer would hit, then paperwork.

**The twenty mechanical checks.** Each gets pass / fail / not-applicable per domain — never a
blank.

Visible to anyone:

1. A privacy policy page exists and is reachable from the footer.
2. It names the actual subprocessors — grep the page for Cloudflare, Contabo, Anthropic, OpenAI,
   Google, AWS, Stripe, Mollie. "Trusted partners" boilerplate is a fail; vague recipient
   language is a recurring enforcement trigger.
3. It states a retention period.
4. It discloses non-EEA transfers and names a mechanism (SCCs, or the DPF).
5. **The cookie banner's reject is as easy as its accept** — same visual tier, one click, not
   behind a sub-menu. This is the AP's published test and the single most likely thing to draw a
   real complaint.
6. **No analytics or ad script fires before consent.** Trace the network on a cold load, then
   after clicking reject. `playwright-cli` can do both.

   **When there is no working browser, say which half you did.** Browser automation breaks
   (a mismatched Nix closure took chromium down on 2026-10-23), and this check must not
   silently degrade into a guess. The fallback is the served HTML, the response headers and
   the app's own cookie-setting code, which is strong evidence of *absence* — a tracker that
   is not in the markup cannot fire. What it cannot see is what an executed script does: a
   cookie set by a same-origin bot-detection or consent script, or a tracker injected at
   runtime. So record checks 5–8 as "static evidence only" and name the one thing you could
   not observe, rather than reporting them as traced.
7. No cookiewall: core content works without accepting. Explicitly prohibited, not a grey area.
8. If the site relies on cookieless analytics being consent-free, **no other third-party
   cookie-setting script is on the same pages** — embeds, tracking fonts, payment widgets. The
   exemption is a property of the whole page, not of the analytics vendor.
9. A contact or complaint address exists (the DSA baseline duty that does apply at this size).
10. Terms exist and mention the 14-day withdrawal right on anything sold to consumers.

What a customer hits:

11. Checkout for immediately-delivered digital content takes an **active, never pre-ticked**
    consent to immediate delivery **and** a separate acknowledgement of losing the withdrawal
    right, with both recorded on the confirmation. Only then may a used period be charged.
12. Any chatbot or assistant UI discloses that it is AI.
13. AI-generated images, audio, video or long text carry a visible or machine-readable marker.
14. In-game currency and purchase UI shows the real-money equivalent — "200 gems" must show €.
15. No pre-ticked marketing consent anywhere in signup or checkout.
16. A DSAR intake channel exists — a `privacy@` address or a form.

Paperwork, checked in the repo:

17. A DPA on file per processor touching personal data.
18. A breach register file exists, even empty.
19. **The Litestream / S3 bucket is in the EU.** Grep the config. A non-EU location is a
    Chapter V transfer needing SCCs and a transfer impact assessment.

    **On Cloudflare R2, read the endpoint, not the region** — and this is not the cheap fix an
    earlier version of this skill claimed. `region = "auto"` is *not* evidence of anything:
    Cloudflare's own EU example uses `region: "auto"` too. Residency comes from the bucket's
    **jurisdiction**, which shows up only in the endpoint host:
    `https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com` is EU-guaranteed, a bare
    `<ACCOUNT_ID>.r2.cloudflarestorage.com` is the `default` jurisdiction with no guarantee.
    A *location hint* (`WEUR`) is best-effort placement, not residency, and is invisible from
    the repo. **A bucket's jurisdiction cannot be changed after creation**, so the fix is
    create-new, re-replicate, verify a restore, then delete the old — which gets more expensive
    the longer it runs, and is the argument for ranking it above the paperwork checks rather
    than below them. Same rule for D1.
20. An Art. 30 ROPA exists and is dated within twelve months.

## 2. The Dutch specifics that change answers

- **72 hours** to notify the AP from *awareness*, through its online portal only — not email, not
  phone. An internal breach register is required whether or not a breach is reportable. The AP
  has fined specifically for being **late** (Booking.com €475k, Marktplaats €380k), so the rule
  is notify incomplete and fast.
- Digital consent age is **16**. Under 12 acts through a legal representative; 12–16 may exercise
  some rights and withdraw consent alone.
- **A DPO is not mandatory** here unless core activity is large-scale monitoring or
  special-category data. Do not flag its absence as a finding.
- DSAR: one month, extendable once by two, with notice sent **before** the first month expires.
- **Micro and small enterprise exemptions are real and worth stating.** DSA's costly tier
  (moderation reports, trusted flaggers, dispute settlement) does not apply. For the European
  Accessibility Act, **services** get a full microenterprise exemption — under 10 employees and
  ≤€2M — including from documenting it, while **products** get none; application software is
  generally a service. Say "exempt today, and this exemption ends at 10 employees or €2M", so
  growth re-opens it rather than it being silently forgotten.

## 3. The AI Act, scoped honestly

He builds *on* GPAI and does not train models, so he is a downstream system provider. Article 53
model documentation is Anthropic's and Google's problem, not his. Two things do apply:

- **Article 50 transparency** — in force since 2 Aug 2026. Disclose AI interaction, mark
  generated content. Checks 12 and 13 cover it, and it costs a line of copy.
- **Article 4 AI literacy** — applies with no headcount floor, softened in July 2026 to "take
  measures to support". For one person this is a short note showing he understands the tools'
  limits. A skill can check that such a note exists; it **cannot** judge whether it is adequate.

**The one place "too small to matter" is false:** anything touching recruitment, HR decisions,
performance evaluation or creditworthiness scoring is **Annex III high-risk regardless of company
size**, with conformity assessment, human oversight and EU database registration — the SME
carve-out only thins the paperwork. Deadline 2 Dec 2027. So ask, per client project, whether it
touches any of those, and raise it as a question rather than deciding it yourself.

## 4. What you must hand to a lawyer

List these as open questions in every report, with what you found and what you could not settle:

- Whether a specific AI product lands in Annex III high-risk.
- Whether the DPF is still safe to rely on for a given subprocessor — the FTC-independence
  ruling of June 2026 and the announced noyb challenge make it valid-but-fragile, and that is a
  legal judgement, not a fact in the repo.
- Whether a given randomised in-game reward is a loot box and whether its design is manipulative
  under the Art. 28 DSA guidelines.
- Whether the accessibility service-not-product classification holds for a specific app.
- Whether the Article 4 literacy measures are *sufficient*.
- Whether a withdrawal-button implementation is legally sufficient — presence is checkable,
  sufficiency is not.
- Whether a DSAR or erasure request was handled correctly in substance.

## 5. Two things in here expire

**Say so in the report rather than letting them rot:**

- The mandatory one-click withdrawal button (herroepingsknop, Art. 6:230oa BW) is live law,
  confirmed 2026-11-02 against primary sources: `wetten.overheid.nl` marks Boek 6's consolidated
  text "Geldend van 16-07-2026", which includes the article, and `officielebekendmakingen.nl`
  resolves "6:230oa" to its implementing chain — Kamerstuk 36860 implementing EU Directive
  2023/2673, AMvB in Staatsblad 2026, 251. It reads as a financial-services instrument only
  because that directive bundled a horizontal amendment into the general Consumer Rights
  Directive; the obligation itself applies to all distance contracts. One imprecision remains —
  the "Geldend van" marker covers all of Boek 6, not this article alone, so the single
  commencement day isn't pinned tighter than "no later than 16-07-2026" (the previously-cited 19
  or 25 June 2026 may still be the article's own date) — but every candidate is already in the
  past, so this changes nothing in practice. Check whether the product sells to consumers at all
  first: with billing switched off it does not bite yet, and it bites the day it is switched on.
- **Loot-box and minor-protection law is the least settled area here** — a fragmented,
  non-harmonised patchwork. Re-research it rather than trusting a cached checklist; the
  Raad van State's March 2022 ruling (packs in a skill-based game with non-tradeable contents are
  not gambling) is the current Dutch footing, but tradeable items remain unsettled.

## 6. The report

Write `docs/legal-audit-<YYYY-MM-DD>.md`: the not-legal-advice line; a table of the twenty checks
with a verdict per domain; failures ordered by how likely they are to be *noticed* rather than by
statutory severity; the lawyer list; and the expiring items with their dates. Fixes you can make
become `claude_todos`; decisions, purchases and anything needing a login become `my_todos` with
`why_yours`.
