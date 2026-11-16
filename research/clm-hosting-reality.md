# clm-hosting-reality

**Question:** What hardware does CLM-8B really need, is Léon's Arc iGPU a realistic middle path, how do we expose it to the tailnet only, and does the spare machine qualify?

**Answer:** The bf16 path needs a 24 GB NVIDIA card: the Qwen3-8B weights alone are 16.4 GB, more than any 16 GB card can hold once vLLM reserves memory for its cache. A Q4_K_M GGUF with full offload needs about 5.5 GB, so an 8 GB card is comfortable and Ryan's 6 GB RTX 2060 is borderline — but nobody has measured how much ranking quality CLM's heads lose on quantised embeddings, which is the real unknown. Léon's own Arc 140T was benchmarked: 64 tokens/s of prompt processing via Vulkan, three times the CPU, but only after disabling fp16 shaders because the Mesa 25.0.7 driver that ships with NixOS 25.05 hangs the GPU; the spare machine could not be checked from here because it is not on the tailnet.

**Confidence:** medium — the VRAM arithmetic and the iGPU numbers are measured or derived from official file sizes; the quality of CLM on Q4 embeddings is unmeasured, and the iGPU result may change a lot with the newer Mesa in 26.05.

**What would change our decision:**
- A measured comparison of CLM's rankings on bf16 versus Q4_K_M embeddings over ~50 real idea pairs. If Q4 holds up, Ryan's 2060 or Léon's laptop can host it and the spare box is unnecessary; this belongs with Ryan's `dedup-without-clm` item.
- The spare machine turning out to have an NVIDIA card with 8 GB or more.
- The Arc 140T numbers after Léon's 26.05 upgrade (Mesa 25.0.7 → 25.3 or newer). If prompt processing lands near the 140V's reported ~490 t/s, the laptop becomes the obvious host.

## Findings

1. **bf16 needs a 24 GB card, not a 16 GB one.** Qwen3-8B has 8.19 B parameters (llama-bench reports `8.19 B`), so bf16 weights are 16.4 GB before the KV cache and activation buffers. vLLM's default `--gpu-memory-utilization 0.9` on a 16 GB card leaves 14.4 GB, which cannot hold the weights; the README's "~16 GB of GPU memory" is the weight size, not a card recommendation. Practical floor: RTX 3090 or 4090 (24 GB), ~€600–700 used for a 3090. Source: parameter count from `llama-bench` output below; vLLM default from [vLLM engine args](https://docs.vllm.ai/en/latest/serving/engine_args.html); `clm-mcp-server/README.md` section A.

2. **Quantised GGUF sizes and what they need with full offload.** Official file sizes from the Qwen repo:

   | quant | file | with 2048-token KV cache and buffers |
   |---|---|---|
   | Q4_K_M | 5.03 GB | ≈ 5.5 GB — fits 8 GB; borderline on 6 GB if the desktop also uses the card |
   | Q5_K_M | 5.85 GB | ≈ 6.3 GB — 8 GB card |
   | Q6_K | 6.73 GB | ≈ 7.2 GB — 8 GB card, tight |
   | Q8_0 | 8.71 GB | ≈ 9.2 GB — 12 GB card; this is the quant the README's CPU path uses |

   KV cache for Qwen3-8B is 144 KiB per token at f16, so 288 MiB at `--max-model-len 2048`; that is why the add-on is small here compared with chat workloads. Kish's and Almar's 4 GB GTX 1650s cannot take any of these fully; partial offload leaves them CPU-bound. Source: [Qwen/Qwen3-8B-GGUF file list](https://huggingface.co/Qwen/Qwen3-8B-GGUF/tree/main); KV-cache per-token figure from a [measured comparison in llama.cpp and vLLM](https://sotaaz.com/post/kv-cache-by-model-en) — UNVERIFIED independently.

3. **Measured on Léon's laptop: Arc 140T via Vulkan does 64 t/s prompt processing, after a workaround.** llama.cpp 5311 from nixpkgs 25.05 with `vulkanSupport = true` (not in the binary cache; built locally in about ten minutes), Qwen3-8B Q4_K_M, full offload (`-ngl 99`), 2026-11-16, machine under normal desktop load:

   | configuration | pp512 (t/s) | tg (t/s) | note |
   |---|---|---|---|
   | Vulkan, defaults | — | — | `vk::DeviceLostError`, kernel logs `i915 GPU HANG … in llama-bench` |
   | Vulkan, `GGML_VK_DISABLE_F16=1` | 64.3 | 4.8 | stable across batch sizes 64–512 |
   | Vulkan, fp16 on, batch 64 | 22.8 | 4.8 | runs, but no faster than CPU |
   | CPU only, 6 or 16 threads | 21.2–21.8 | 1.4–1.5 | |

   The driver reports `matrix cores: none`, so the 140T's XMX units are unused under this Mesa; the GPU hang is an fp16-shader problem in Mesa 25.0.7 on Arrow Lake, not a memory problem. For reference, an Arc 140V (Lunar Lake) on a current driver has been reported at 487.6 pp512 / 19.2 tg128 for the same model and quant, so the gap to expect from a newer Mesa is large. Source: local runs, `llama-bench`; `journalctl -k`; [llama.cpp discussion #12570](https://github.com/ggml-org/llama.cpp/discussions/12570) for the 140V figure.

4. **What 64 t/s means for the crew-memory use.** Embedding is prompt processing only, there is no generation. A 200-token idea takes about 3 s; a first-time backfill of 300 ideas is about 15 minutes once, after which CLM's own candidate cache makes re-ranking cheap. That is usable for a nightly or on-demand dedup pass, not for interactive use, and about twice the README's 4-vCPU Xeon container (≈ 30 t/s). Source: finding 3; README "Measured in a 4-vCPU Xeon container".

5. **SYCL is not a better route today.** Intel archived its IPEX-LLM fork in January 2026; Ollama and LM Studio use Vulkan on Arc. SYCL has had iGPU prompt-processing fixes but worse generation throughput than Vulkan in reports, and nixpkgs' `llama-cpp` has no SYCL flag. Léon's installed `ollama` (0.11.10) ships only CPU `libggml` backends, so it cannot be used for this either. Source: [Intel Arc llama.cpp status, 2026](https://www.runaihome.com/blog/intel-arc-llama-cpp-2x-speed-optimization-2026/) — UNVERIFIED blog; local `ls` of the ollama package.

6. **`llama-server` can replace the Python embedding script.** The nixpkgs build has `llama-server --embeddings --pooling last -ngl 99 -c 2048`, serving an OpenAI-compatible `/v1/embeddings`; the repo's `llamacpp_embeddings.py` does the same through `llama-cpp-python` with `LLAMA_POOLING_TYPE_LAST` and `normalize=False`. UNVERIFIED: whether `llama-server`'s output normalisation matches what the CLM heads were trained on; the script is the known-good path and should be kept until that is checked. Source: `llama-server --help` from the local build; `clm-mcp-server/scripts/llamacpp_embeddings.py` lines 84–100.

7. **Tailnet-only exposure.** `clm-serve --host $(tailscale ip -4) --port 8700` with `CLM_API_KEY` set binds only the tailnet address; the embedding backend (vLLM or llama-server) stays on `127.0.0.1`. On NixOS, open the port on the interface, not globally: `networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8700 ];`. Binding to the tailnet IP races `tailscaled` at boot (`bind() … Cannot assign requested address` is the known symptom); the simplest cure is to bind `0.0.0.0` and rely on the interface-scoped firewall, which is equally closed as long as the global firewall stays on. Tailscale ACLs can further limit the port to the four crew devices. Clients set `CLM_BASE_URL=http://100.x.y.z:8700` and `CLM_ALLOW_INSECURE_HTTP=1`, because the MCP server refuses plain HTTP to any non-local host otherwise. Source: README sections B and "Exposure"; [NixOS + Tailscale bind race](https://gquetel.fr/misc/waiting-tailscale-interface/).

8. **`services.tailscale.serve` does not exist in NixOS 25.05 or 26.05.** A summary of the 26.05 release notes claimed it does; the module source in both locked nixpkgs revisions has only `extraSetFlags`, `interfaceName`, `openFirewall` and friends. `tailscale serve --bg --http=8700 …` is imperative and adds nothing here, since CLM speaks plain HTTP with a bearer token. Source: `nixos/modules/services/networking/tailscale.nix` in nixpkgs `ac62194` (25.05) and `f1e5c35` (26.05), checked locally.

9. **`clm-serve` authentication is one static bearer token.** `CLM_API_KEY` makes it require `Authorization: Bearer <key>`; there are no users, roles or TLS. Device and port come from `--device cpu|cuda`, `--port`, `--emb-url`; `--action-cache` reserves device memory for cached candidate embeddings. Source: [contrastive-lm on PyPI](https://pypi.org/project/contrastive-lm/); README section "Exposure".

10. **The spare machine is not reachable from here.** The tailnet currently shows only this laptop and a phone, so no remote check was possible. Léon runs, on the box:
    ```
    nvidia-smi --query-gpu=name,memory.total --format=csv || lspci | grep -iE 'vga|3d'
    ```
    and reads the result against this table:

    | GPU memory | verdict |
    |---|---|
    | NVIDIA ≥ 24 GB | hosts the bf16 reference path with vLLM |
    | NVIDIA 8–23 GB | hosts Q4_K_M–Q8_0 with full offload; quality to be measured first |
    | NVIDIA 6 GB | Q4_K_S or IQ4_NL only, borderline; same as Ryan's 2060 |
    | AMD, Intel or none | no better than Léon's laptop; use the laptop or drop CLM |

## Not checked

- Ranking quality of CLM on quantised embeddings. The README states the Q8_0 CPU path was never compared with bf16; nothing here changes that, and it is the single most important unknown.
- fp8 weights in vLLM on an RTX 40-series card (would halve the bf16 footprint to ~8.5 GB) — a different numeric path than the heads were trained on, untested.
- AMD or ROCm hosts.
- Léon's laptop after the 26.05 upgrade; the benchmark should be rerun then, it takes two minutes with the build cached: `llama-bench -m Qwen3-8B-Q4_K_M.gguf -ngl 99 -p 512 -n 8` with and without `GGML_VK_DISABLE_F16=1`.
