# free-llm-router-2
> Second pass, kept for comparison. **Superseded by `free-llm-router.md`**, which read the providers' own terms. This pass leaned on secondary sources, and its Groq + Cerebras advice is stale: Cerebras is no longer free (finding 4 here says so), and it missed Google's EEA paid-only clause and OpenRouter §7.3.

**Question:** Does the GitHub project in the reel (7 billion free tokens a month, 600 models, failover) hold up, and is it safe and within terms for non-secret bulk work such as summarising video transcripts?

**Answer:** The project is FreeLLMAPI (tashfeenahmed/freellmapi, MIT). It is a self-hosted router that rotates across the free tiers of providers you sign up for yourself, so it is usable for non-secret transcript summarising if each person runs their own copy on their own keys. The reel's numbers are an older snapshot (7.4B tokens, 635 endpoints, 34 providers), and the README now says 10.1B, 1,313 endpoints and 87 providers. None of these figures is derived or checkable in the README. Do not send anything private, because Google's free tier and some OpenRouter and Mistral free routes train on prompts, and one shared crew instance would breach the project's own terms guidance.

**Confidence:** Medium, because provider terms came from official pages only for Google, Groq, Cerebras and OpenRouter, and the code was not read.

**What would change our decision:**
- If the crew wants one shared endpoint for all four people, or wants several accounts per provider to get more quota. Both are against the project's own rules of thumb and likely against provider terms.
- If transcripts turn out to contain client or personal data. Then use only Groq or Cerebras (no training by contract), or a paid API.

## Findings

1. **Identification.** The reel matches FreeLLMAPI, a self-hosted OpenAI-compatible `/v1` gateway with smart routing, automatic failover on 429/5xx and encrypted keys. It is labelled "personal experimentation only". Forks and clones still carry the older tagline "7.4 billion tokens per month. 34 free LLM providers. 635 free model endpoints", which is where the reel's "7 billion / 600 models" comes from. [fork with old tagline](https://github.com/Aniketchavan7/freellmapi), [clone claiming 600+](https://github.com/PryxIntel/free-llm-api), [upstream repo](https://github.com/tashfeenahmed/freellmapi). Other repos named "free-llm-router" exist, such as [Pr0fess0rOP/free-llm-router](https://github.com/Pr0fess0rOP/free-llm-router), a BYOK router. The reel's numbers do not match them.

2. **The "7 billion" claim is stale and unverifiable.** The upstream README now says about 10.1B tokens a month, 87 providers, 736 model families and 1,313 free endpoints, using the word "roughly". It shows no per-provider arithmetic. Per-model budgets are said to live on the project's own site, [freellmapi.co/models](https://freellmapi.co/models), which was not checked. The figure is a sum of advertised free-tier caps, not a measured throughput. [README](https://github.com/tashfeenahmed/freellmapi). UNVERIFIED: the 7.4B and 10.1B totals themselves.

3. **The "600 models" claim is stale and inflated by counting.** The README counts "endpoints", and the same model on different providers counts several times. The 1,313 breaks down as 1,137 chat, 29 image, 41 audio, 68 embeddings, 19 transcription, 6 video and 13 decision. Only 12 providers are named in the README, with "75 more" unnamed. Many are anonymous-access or tiny-limit sources. [README](https://github.com/tashfeenahmed/freellmapi), [raw README](https://raw.githubusercontent.com/tashfeenahmed/freellmapi/main/README.md). UNVERIFIED: how many endpoints are actually usable at once. The provider list in the code was not read.

4. **The pool is stale for at least Cerebras.** Cerebras no longer has a permanent free tier. It now gives $5 in credits for 30 days after you add a payment method, with no renewing no-cost tier. Any guide that sums "1M tokens/day from Cerebras" is out of date. [Cerebras rate limits](https://inference-docs.cerebras.ai/support/rate-limits)

5. **What "pooling" means here.** The router rotates across keys and providers you register, with per-key rate tracking and cooldowns. The README does not say whether several keys per provider are supported. The project's own terms review gives these rules of thumb: one account per provider, no resale, do not share your endpoint with other people, do not use a free tier as paid production. The README says the upstream terms still apply to proxied traffic and that you are responsible for complying. The review is informational and says it is not legal advice. [README disclaimer](https://github.com/tashfeenahmed/freellmapi), [ToS review (May 2026)](https://github.com/tashfeenahmed/freellmapi/blob/main/docs/en/architecture/00-high-level-index.md)

6. **Does pooling break provider terms?** Using one account per provider and failing over between providers is not itself a breach. The risks are:
   - Several accounts per provider to multiply quota.
   - One endpoint shared by four people.
   - Google's March 2026 wording narrowing the API to "professional or business purposes".
   - Cohere's terms, which exclude personal, family or household use. The project says "Avoid" for Cohere.

7. **Privacy and retention.** The router runs locally. The README says requests go straight from your machine to the providers you enable, and the catalog server never sees prompts or keys. Prompt compression and caching are opt-in. Prompt handling is therefore decided by each upstream provider, and the router will fail over to whichever provider is available. [README](https://github.com/tashfeenahmed/freellmapi)

8. **Provider table.**

| Provider | Free-tier limit | Trains on prompts? | Retention | Multi-account / pooling / resale |
|---|---|---|---|---|
| Google Gemini (AI Studio) | Limits apply per project, not per key. Model-specific, and the docs gave no full table ([limits](https://aistudio.google.com/docs/rate-limits)). | YES on unpaid services. Google uses submitted content to improve its products, and human reviewers may read it. It says "Do not submit sensitive, confidential, or personal information" ([terms](https://aistudio.google.com/docs/terms)). | No general period stated. Grounding with Google Search keeps data for 30 days. | The terms page has no explicit multi-account ban, but Google's API ToS was not read. The project rates this "Caution" ([review](https://github.com/tashfeenahmed/freellmapi/blob/main/docs/en/architecture/00-high-level-index.md)). |
| Groq | UNVERIFIED. No official limit table found. | Not per [your-data page](https://console.groq.com/docs/your-data), which is silent on training. A secondary source says the Services Agreement bars it. UNVERIFIED in primary text. | No retention of inference data by default. ZDR toggle available. Secondary sources say up to 30 days of abuse and troubleshooting logs. | "Likely OK" per the project's review. UNVERIFIED against Groq's own terms. |
| Cerebras | $5 credit for 30 days, then pay as you go. On gpt-oss-120b the trial is 5 RPM and 1M tokens a day ([limits](https://inference-docs.cerebras.ai/support/rate-limits)). | Secondary sources say no training right in the terms. UNVERIFIED in primary text. | Secondary sources quote the privacy policy as "do not retain inputs and outputs". UNVERIFIED in primary text. | API keys may not be sold or transferred. Project rates it "Likely OK". |
| Mistral (Experiment plan) | UNVERIFIED. No official limit table found. | YES by default on the free plan, with an opt-out in the Admin Console privacy settings. Per Mistral help-centre text reported by secondary sources, so UNVERIFIED in primary text. | 30 rolling days for abuse monitoring, per secondary sources. | "Likely OK" for personal or internal use per the project. UNVERIFIED against Mistral's own terms. |
| OpenRouter (`:free` models) | Request-based caps, not token caps. UNVERIFIED in primary text. | OpenRouter itself does not train unless you opt in (off by default, 1% discount) ([docs](https://openrouter.ai/docs/guides/privacy/data-collection)). The upstream host of each free model may train. Secondary sources say NVIDIA, Thinking Machines, Liquid and Poolside free routes do. UNVERIFIED in primary text ([TrueFoundry](https://www.truefoundry.com/blog/openrouter-free-models-whats-actually-free-and-what-it-costs-you)). | OpenRouter stores no prompts by default. Flagged content and metadata are exceptions, and "ZDR only" excludes safety-retention endpoints. | Its April 2026 update tightened the no-resale and no-competing-service terms. A private single-user proxy is considered fine by the project. |
| NVIDIA NIM | 40 RPM recurring. Trial terms limit use to evaluation. | Secondary sources say free-tier traffic is logged to improve models. UNVERIFIED in primary text. | UNVERIFIED | Project rates it "Caution". |
| Cloudflare Workers AI | UNVERIFIED | UNVERIFIED | UNVERIFIED | Project rates it "Ambiguous". |
| Cohere | UNVERIFIED | UNVERIFIED | UNVERIFIED | Project says "Avoid". Its terms exclude personal, family or household use. |
| Z.ai and Zhipu | UNVERIFIED | UNVERIFIED. Chinese-hosted. | UNVERIFIED | Zhipu is "Likely OK" (personal or non-commercial research carve-out). Z.ai is "Caution" (anti-redirect clause, no personal-use carve-out). |
| Other 75 providers (HuggingFace, ModelScope, OpenCode Zen and others) | Not checked | Not checked | Not checked | Not checked |

9. **Safe for transcript summarising?** It is safe only if the transcripts are public or non-secret and you accept that some pooled providers may train on them. The router does not pick providers by privacy policy, so a transcript can land on Google (trains, human review) or a training-enabled OpenRouter free route. The mitigation is to enable only Groq and Cerebras (no training by contract per secondary sources, no default retention). If you use OpenRouter, set its data-collection controls, such as the ZDR-only privacy setting. Whether the router lets you restrict failover to an allow-list of providers is UNVERIFIED. The code was not read.

10. **Fit for a crew of four on NixOS.** Each person runs their own instance with their own keys, which follows the project's rules. One shared instance would violate "do not share your endpoint". A NixOS package or module for it is UNVERIFIED. It is a Node app with Docker docs, so a container or `buildNpmPackage` is likely needed. Free-tier caps are small, and the README itself says free tiers are not a stable base for anything real.

## Not checked
- The repo code itself (provider list, multi-key handling, routing and allow-list logic, telemetry). The fetch tool returned rendered README and doc pages only. The 7.4B to 10.1B history was inferred from fork snapshots, not from commit history.
- [freellmapi.co/models](https://freellmapi.co/models), where per-model token budgets are said to live.
- Primary-source terms for Groq (Services Agreement), Cerebras (ToS and privacy policy), Mistral (help centre and commercial terms), NVIDIA, Cloudflare, Cohere, Z.ai and Zhipu. Secondary summaries or the project's own review were used, and those cells are marked UNVERIFIED.
- Google's wider API Terms of Service and Prohibited Use Policy, for multi-project or multi-account rules.
- The other 75 providers.
- Whether the project's last-commit date is recent. The README shows 1,175 commits and about 58k stars, but the date was not confirmed.
