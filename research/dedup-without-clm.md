# dedup-without-clm

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Measured on Léon's laptop** (Core Ultra 9 285H, CPU only, `python3Packages.fastembed` 0.6.1 from nixpkgs 25.05, `BAAI/bge-small-en-v1.5`): 500 synthetic 120-word paragraphs embed in 38.8 s (77 ms each), one new paragraph takes 101 ms, and ranking it against 500 stored vectors with plain NumPy takes 2.8 ms. Model load plus first download: 2.8 s. The "well under a second per idea" estimate holds; fastembed is 0.8.0 on nixpkgs 26.05, so both releases have it.
>
> **What this changes:** this is now the design. On 16 November Léon parked CLM until a machine with a 24 GB NVIDIA card or a suitable spare box exists (see `clm-hosting-reality`), so the dedup pipeline is bge-small through FastEmbed, brute-force cosine, top three to Laya's calibrated yes/no. The hand-made 20–30 pair test set in the recommendation is the next concrete task for crew-memory. Ideas should be written in English; the English-only model is then fine.

---

*Owner: Ryan · researched 16 Nov 2026 · web research only. Nothing was timed: this session has no access to Ryan's laptop or GPU, so the "time B on GPU vs CPU" part of the brief is not done.*

**Question:** For spotting when two of four people record a similar project idea among a few hundred short paragraphs, do we need the 8B contrastive model, or does a small CPU embedding model plus a yes/no check do the job?

**Answer:** B now, A later only if B visibly misses things: a small embedding model ranks a few hundred paragraphs on any laptop CPU in well under a second, and the existing calibrated yes/no check covers the precision the small model lacks. On similarity-style benchmarks the small models sit within a few points of the 8B class; the large gap is on hard retrieval, which is not this task. Start with `bge-small-en-v1.5` (MIT) if ideas are written in English.

**Confidence:** medium — model sizes, licences and benchmark scores are from papers and model cards; no published benchmark matches "near-duplicate project ideas at n ≈ 500", and no latency was measured on our hardware.

**What would change our decision:**
- If a hand-made test set of 20–30 known overlapping idea pairs shows B ranking the true match outside the top 3 more than occasionally, move to a mid-size model first (finding 7), and to A only after that.
- If ideas are written in Dutch or mixed languages, the English-only models are the wrong pick (finding 8).

## Comparison

| | A. 8B contrastive model | B. Small embedding model + yes/no check |
|---|---|---|
| Hardware | ~16 GB GPU; none in the crew | Any laptop CPU |
| Quality on similarity tasks | STS 88.6, pair classification 87.5 (Qwen3-Embedding-8B, as a stand-in) | STS benchmark ~84.6 for the smallest model; duplicate-detection differences between small and large embedders reported as under 0.02 AUC in one study |
| Quality on hard retrieval | ~69 | ~43–54 |
| Speed, one paragraph | Not applicable without the GPU | Roughly 5–30 ms on CPU, depending on model and runtime |
| Disk / RAM | ~16 GB VRAM, or ~9 GB RAM quantised and slow | ~90–300 MB model; runtime from tens of MB to several GB depending on the stack |
| Licence | Apache-2.0 (Qwen3-Embedding) | MIT or Apache-2.0 |

## Findings

1. **The candidates, with sizes and licences.**

   | Model | Parameters | Dimensions | Max input | Licence |
   |---|---|---|---|---|
   | all-MiniLM-L6-v2 | 22.7M | 384 | 256 word pieces | Apache-2.0 |
   | bge-small-en-v1.5 | 33.4M | 384 | 512 tokens | MIT |
   | e5-small-v2 | 33.4M | 384 | — | MIT (from memory: UNVERIFIED) |
   | nomic-embed-text-v1.5 | 137M | 768 | 8,192 tokens | Apache-2.0 |

   All four can be used in a commercial setting. [comparison table with licences](https://supermemory.ai/blog/best-open-source-embedding-models-benchmarked-and-ranked/) · [parameter counts](https://arxiv.org/pdf/2602.08740)

2. **Where the big models really win: retrieval.** On the MTEB English v2 retrieval score, bge-small-en-v1.5 gets 53.86 and all-MiniLM-L6-v2 gets 42.92, while Qwen3-Embedding-8B — an 8B model of the same family the CLM encoder is built on — gets 69.44. That is a gap of roughly 16 to 27 points. Retrieval here means finding a relevant passage for a question across a large, varied corpus. [small-model scores](https://supermemory.ai/blog/best-open-source-embedding-models-benchmarked-and-ranked/) · [Qwen3-Embedding-8B model card](https://huggingface.co/Qwen/Qwen3-Embedding-8B)

3. **Where the gap is small: "are these two texts about the same thing".** That is the task at hand.
   - Qwen3-Embedding-8B scores 88.58 on semantic textual similarity and 87.52 on pair classification (MTEB English v2). [model card](https://huggingface.co/Qwen/Qwen3-Embedding-8B)
   - all-MiniLM-L6-v2, the smallest candidate, is listed at 84.6 Spearman on the STS benchmark. Different test sets, so not a like-for-like subtraction, but the order of magnitude is "a few points", not fifteen. [model summary citing the SBERT card](https://mixpeek.com/model/sentence-transformers/all-MiniLM-L6-v2)
   - A 2026 study on detecting cloned text compared MiniLM-L6 with two models roughly fifteen times larger and found a mean AUC difference under 0.02. [arXiv 2608.24461](https://arxiv.org/pdf/2608.24461)
   - A 2026 survey of embedding-model choice recommends MPNet/MiniLM-class models for duplicate detection, citing strong performance at modest cost, and lists a MiniLM variant as the top scorer on Quora duplicate-question retrieval (87.75). [arXiv 2607.23507](https://arxiv.org/html/2607.23507v1)
   - The original MTEB paper already noted that a model almost 50 times smaller matched the then-largest model on clustering. [MTEB paper](https://arxiv.org/pdf/2210.07316)

   No published benchmark covers the 8B *contrastive ranking* model in question against small models on near-duplicates at this scale: the accuracy gap for our exact setup is UNVERIFIED.

4. **bge-small over MiniLM.** Same 384 dimensions, 512-token input instead of 256 (a paragraph can exceed 256 word pieces), and roughly ten points higher on retrieval for a small increase in size. Multiple comparisons say there is little reason to choose MiniLM for new work. [benchmark comparison](https://www.generalcompute.com/blog/embedding-model-benchmarks-speed-vs-quality-for-rag-retrieval) · [MiniLM guide](https://tokenmix.ai/blog/all-minilm-l6-v2-free-local-embedding-guide-2026)

5. **CPU latency — published figures vary widely; none is from our laptops.**
   - all-MiniLM-L6-v2: about 5–8 ms per text on CPU in two write-ups. [one](https://markaicode.com/usecases/sentence-transformers-use-cases-production-workflows/) · [two](https://mixpeek.com/model/sentence-transformers/all-MiniLM-L6-v2)
   - The same model on a server CPU: 120–150 texts per second with stock sentence-transformers, about 400 per second with the ONNX-based FastEmbed. [FastEmbed vs sentence-transformers](https://inferensys.com/differences/private-rag-vs-fully-local-ai-architectures/local-embedding-model-alternatives/fastembed-vs-sentence-transformers)
   - A tutorial measuring an unoptimised run reports 35 sentences per second on CPU. [tutorial](https://theneuralbase.com/sentence-transformers/learn/beginner/slow-encoding-on-cpu/)

   Taking the pessimistic end: 30 ms to embed one new paragraph. bge-small has twice the layers of MiniLM, so expect up to about double. Comparing one vector against 500 stored vectors is 500 dot products of 384 numbers — microseconds, with plain NumPy and no vector database. Embedding the whole backlog of 500 once takes seconds to tens of seconds. Then add the existing yes/no check at about 0.2 s for the top match. Total for a new idea: well under a second. All of this is arithmetic on third-party numbers: UNVERIFIED on our hardware.

6. **Disk and RAM.** The model files are small (roughly 90 MB for MiniLM, under 300 MB for nomic). The runtime dominates: one comparison puts bge-small at about 130 MB of memory under FastEmbed versus about 480 MB under sentence-transformers, and a PyTorch-based install is measured in gigabytes on disk. A llama.cpp binary plus a quantised GGUF file is tens of megabytes plus the model. [FastEmbed vs sentence-transformers](https://inferensys.com/differences/private-rag-vs-fully-local-ai-architectures/local-embedding-model-alternatives/fastembed-vs-sentence-transformers) · [serving embeddings with llama.cpp](https://dev.to/multigrid/serving-embeddings-with-llamacpp-3hof) · [nomic footprint](https://www.tigerdata.com/blog/finding-the-best-open-source-embedding-model-for-rag)

7. **A middle step exists before A.** If the small model is not good enough, the same Qwen3 family has a 0.6B model scoring 86.57 on STS and 84.37 on pair classification — close to the 8B's 88.58 and 87.52 — which runs on CPU or Ryan's 6 GB GPU. Not evaluated further. [Qwen3-Embedding model card](https://huggingface.co/Qwen/Qwen3-Embedding-8B)

8. **Language.** bge-small-en, e5-small-v2 and all-MiniLM-L6-v2 are English models. If ideas are recorded in Dutch or a mix, use a multilingual small model instead — `multilingual-e5-small` exists at about 118M parameters and 384 dimensions. Its quality on Dutch was not checked. [parameter table](https://arxiv.org/pdf/2602.08740)

9. **Packaging for NixOS.** Three routes, all with packages already in nixpkgs:
   - **FastEmbed** (`python3Packages.fastembed`, Apache-2.0) — ONNX runtime, no PyTorch, smallest footprint. bge-small-en-v1.5 is one of its standard models. [nixpkgs package record](https://packages.ecosyste.ms/registries/nixpkgs-unstable/packages/python313Packages.fastembed)
   - **sentence-transformers** (`python3Packages.sentence-transformers`, Apache-2.0) — simplest API, pulls in PyTorch. [nixpkgs package source (mirror)](https://tangled.org/pyrox.dev/nixpkgs/blob/24.11-pre/pkgs/development/python-modules/sentence-transformers/default.nix)
   - **llama.cpp** (`llama-cpp`, with a `services.llama-cpp` NixOS module) in embedding mode with a GGUF model — no Python at all; the same binary could later serve a bigger model. [NixOS wiki: llama-cpp](https://wiki.nixos.org/wiki/Llama-cpp)

   In every route the model weights are a separate download; for a reproducible flake they should be fetched by hash rather than at first run. Whether these package versions are current in 26.05 and build on 25.05: UNVERIFIED.

10. **Why the two-stage shape in B is right.** Cosine similarity gives a ranking, not a decision: there is no universal threshold at which two ideas "are the same". Ranking with the embedding model and then asking the calibrated yes/no model about only the top one to three candidates uses each tool for what it is good at, and keeps the slow step to a handful of calls. (Design reasoning; not from a source.)

## Recommendation

**B now, A later — and probably never A.** Concretely: bge-small-en-v1.5 through FastEmbed, embeddings stored next to the idea notes, brute-force cosine, top 3 passed to the existing yes/no check. Before trusting it, write 20–30 pairs of ideas by hand that you would want flagged and 20–30 you would not, and see where they land. If that test fails, try Qwen3-Embedding-0.6B before anything that needs a 16 GB GPU.

## Not checked

- **Timing on real hardware** — CPU or Ryan's RTX 2060. The brief asked for GPU versus CPU timing; that has to be run on the machine. At this size the GPU will not matter: the per-idea cost is already milliseconds.
- **The CLM model itself.** I had no access to `contrastive-lm` or its evaluation numbers; Qwen3-Embedding-8B was used as a published stand-in for "an 8B model built on Qwen3", and it is an embedding model, not a contrastive ranker.
- **Our own data.** No benchmark resembles a few hundred project-idea paragraphs from four people. The hand-made test set in the recommendation is the real answer.
- **Model cards on Hugging Face** for the four small models were not opened; licences for three come from a comparison table, and e5-small-v2's is from memory.
- **Dutch-language quality** of any candidate.
- **Hybrid approaches** (keyword overlap plus embeddings), which one near-duplicate paper suggests can beat embeddings alone for literal near-copies — less relevant for "same idea, different words".
