# booking-stack-licences

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Confirmed:** Cal.com's own v6.4 changelog (15 April 2026) says the commercial codebase "will no longer be publicly available" and relaunches the open-source code as Cal.diy under MIT.
>
> **Added:** Easy!Appointments, the one candidate left unchecked, is GPL-3.0 (not AGPL), has 4.5k stars and commits this week. GPL-3.0 has no network clause, so hosting it for clients, modified or not, obliges nothing; only distributing binaries would. It is PHP + MySQL, so it does not fit the SvelteKit + FastAPI + SQLite stack and would be a parallel system to maintain. It is a fair fallback for a first salon in a hurry, not the design.
>
> **What this changes:** nothing; option C (build it) stands, with the correctness list in finding 8 as the acceptance test. The hosted-tier numbers and the Cal.eu closure remain UNVERIFIED.

---

*Owner: Almar · researched 16 Nov 2026 · I am not a lawyer; the licence and data-protection points are a starting position, not legal advice.*

**Question:** For the appointment booking every hairdresser site needs, should we self-host an open-source scheduler, use a free hosted one, or build it ourselves?

**Answer:** No option is disqualified on licence — but the premise has changed: Cal.com went closed source in April 2026, and what is left to self-host (Cal.diy, MIT) is a single-user scheduler its own publisher says is not for production. Build it (option C): it is the only route that is free at five salons with several staff each, keeps EU customers' names and phone numbers on a server we choose, and has no vendor to change terms on us. The cost is our time and owning the hard parts — double-booking, time zones, reminders — ourselves.

**Confidence:** medium — the Cal.com change is confirmed by Cal.com's own changelog and repository; the hosted free-tier limits are from comparison articles that contradict each other in places, and none of the three options was tried.

**What would change our decision:**
- If a typical client is a one-chair salon with a single calendar, a hosted free plan (or Cal.diy) is enough and building is overkill for the first clients.
- If nobody has two to four weeks for a careful first version, start clients on a hosted plan and build behind it.

## Comparison

| | A. Self-host open source | B. Hosted free tier | C. Build (SvelteKit + FastAPI + SQLite) |
|---|---|---|---|
| Licence risk | None for selling. Cal.diy is MIT. | None — it is a service, not code. Terms of service not read. | None. Ours. |
| Fits a multi-staff salon | No. Cal.diy removed teams and workflows. | Mostly no. Free plans stop at one user, or cap bookings. | Yes, by design. |
| Cost at five client sites | A VPS. But one Cal.diy user per instance means workarounds. | $0 only for one-person salons. Otherwise roughly $12 per staff member per month on Cal.com. | One small VPS shared by all five, plus email sending. |
| Data protection (EU names and phone numbers) | Good — our server. | Weakest — data at a US vendor; Cal.com's EU region reportedly closed 1 Nov 2026. | Good — our server, our choice of EU host. |
| Lock-in | Medium. Community-maintained fork, uncertain future. | High. Their features, their pricing, their branding. | None, but we carry all maintenance. |

## Findings

1. **Cal.com is no longer AGPL open source.** In mid-April 2026 Cal.com moved its production code to a private repository. Its own changelog says the free and open-source code was relaunched as Cal.diy under the MIT licence, for self-hosting at your own risk, and that the commercial edition's code is no longer publicly available. The brief's "Cal.com — state its licence (AGPL)" describes the situation before that date. [Cal.com v6.4 changelog (official)](https://cal.com/blog/calcom-v6-4) · [independent report](https://itsfoss.com/news/cal-com-goes-proprietary/)

2. **Cal.diy is MIT, so selling is allowed — but it is the wrong shape.** The repository states the whole codebase is MIT with no enterprise code. It also states that Teams, Organizations, Insights, Workflows and SSO have been removed. Without teams there is no "availability per staff member"; without workflows the reminder automation is gone. For a salon with three stylists that is the core of the product. [Cal.diy README (official)](https://github.com/calcom/cal.diy/blob/main/README.md)

3. **The publisher says not to use Cal.diy in production.** The repository and documentation both carry a warning that it is strictly recommended for personal, non-production use, and direct commercial users to Cal.com. That is not a licence restriction — MIT permits commercial use regardless — but it tells you how much support and security attention to expect. One German write-up adds that the published Docker image for Cal.diy had no tags as of mid-October 2026 and that the fork is maintained by former interns. [Cal.diy docs (official)](https://www.cal.diy/) · [Cal.diy repository](https://github.com/calcom/cal.diy) · [German analysis](https://pareto.space/a/naddr1qqdxxctv943k7mfdwdjkccnnwskksmmnw3jkutfjxqervqgcwaehxw309ahx7um5wgh8qctjv46x7tnnwpskxegzyrqm4a8hfnvzn93c9zca4rtnu5kvjn92dkxuj38hefzs5awykvc37qcyqqq823ckxkvc3) (third-party)

4. **What AGPL would have meant, in plain words — since the brief asked.** AGPL does not forbid selling or hosting for clients. Its extra rule (section 13) is: if you *modify* the program and let people use it over a network, you must offer those users the source of your modified version. Running it unmodified triggers nothing. So under the old licence, a customised Cal.com hosted for a salon would have obliged us to publish our changes to that salon's customers — awkward, not prohibitive. This still applies to the last AGPL release (v6.2.0, March 2026) if anyone considers running it, but that version's team features sat in a separately licensed commercial folder and it no longer receives updates. [AGPL explained](https://socket.dev/glossary/agpl) · [opensource.com on section 13](https://opensource.com/comment/115426) · [last AGPL image and licence files](https://pinggy.io/blog/self_hosted_calendly_alternatives/)

5. **Other self-hostable schedulers exist; none was evaluated.** Round-ups after the Cal.com change name Easy!Appointments, Tymeslot (AGPL-3.0) and Rallly among the alternatives. Easy!Appointments is the one aimed at service businesses with staff and services; its licence and fitness were not checked here. [round-up](https://pinggy.io/blog/self_hosted_calendly_alternatives/) · [second round-up](https://use-apify.com/blog/calendly-alternatives-2026)

6. **Hosted free tiers end at the second staff member, or at a booking cap.** From comparison articles, late 2026:
   - **Cal.com Free:** one user, unlimited event types and bookings, branding stays; teams cost $12 per user per month. [Cal.com's own comparison](https://cal.com/blog/best-free-appointment-scheduling-apps) · [independent table](https://zcal.co/blog/free-appointment-scheduling-apps)
   - **Calendly Free:** one event type, one calendar — a salon with "cut", "colour" and "cut + colour" already exceeds it. [comparison](https://bookmyappointments.com/best-free-appointment-scheduling-software/)
   - **Setmore Free:** reported as up to 4 users, and 200 bookings a month. [comparison](https://simplybook.me/en/blog/best-free-booking-software) (written by a competitor)
   - **Square Appointments Free:** sources disagree — some say unlimited staff calendars per location, others say one staff member — and it takes a fee on every card payment. Whether Square operates in the Netherlands at all: UNVERIFIED. [says unlimited staff](https://automahawk.com/en/blog/free-appointment-booking-apps/) · [says one staff](https://meetergo.com/en/magazine/best-free-scheduling-software)

   A free tier that turns paid at the second stylist is the finding the constraint asked for: at five salons with three staff each, Cal.com Teams would be about 15 × $12 = $180 a month.

7. **Data protection: hosting it ourselves makes us the processor.** The data is salon customers' names and phone numbers. Each salon decides why it is collected, so the salon is the controller; if we host the booking system, we process that data on the salon's behalf and need a written data processing agreement with each salon under GDPR Article 28. With a hosted scheduler, the vendor is a further processor that must be named in that agreement, and data leaves for a US company. A review dated two days ago says Cal.com's EU region (Cal.eu) closed on 1 November 2026 — one source, with a commercial interest, so UNVERIFIED. [agency responsibilities under GDPR](https://www.iubenda.com/en/help/26171/-web-agency-responsibilities-gdpr) · [when a DPA is required](https://openforest.co/articles/data-processing-agreement) · [Cal.eu closure claim](https://meetergo.com/en/magazine/cal-com-review)

8. **Building it: where the risk actually is.** No source needed for the licence — it is our code. The risk is correctness in exactly the places the brief lists. These are engineering judgements, not sourced findings:
   - **No double-booking:** enforce it in the database (a transaction plus a uniqueness or overlap check), not only in the UI.
   - **Time zones and DST:** store instants in UTC plus the salon's named zone (for example `Europe/Amsterdam`); compute opening hours in local time so the two clock changes a year do not shift appointments.
   - **Reminders:** need a scheduled job and an email sender; a free sending tier's limits were not checked.
   - **SQLite:** one file per salon keeps clients separated and makes backup and deletion requests simple; one writer at a time is fine at salon volume.

9. **Cost at five client sites, summarised.** A: one or more VPS instances, already allowed under the "bought deliberately to put something live" rule, but Cal.diy's single-user design means one instance or account per stylist. B: $0 for one-person salons only. C: one small VPS for all five and an email sender. VPS and email prices were not looked up.

## Not checked

- **Nothing was installed or trialled.** Cal.diy was not run; no hosted plan was signed up for.
- **Official pricing pages** for Calendly, Setmore and Square were not opened; the free-tier limits are from comparison articles, several written by competitors, and they conflict on Square.
- **Easy!Appointments** — the most plausible "adopt" candidate for salons after Cal.com's change. Its licence, staff model and maintenance status deserve their own short check before C is final.
- **Terms of service** of the hosted schedulers, including whether reselling or embedding in a client site we charge for is allowed.
- **Dutch and EU specifics** beyond Article 28: cookie consent on the booking page, retention periods, and whether SMS reminders (phone numbers) change anything.
- **Payments, deposits and no-show fees** — the brief lists no-show handling; whether that means charging a card was not explored.
- **Email deliverability and free sending limits.**
- **Build effort.** "Two to four weeks" is my estimate, not a measured figure.
