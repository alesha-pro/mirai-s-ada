# Mirai S 27B on a 12 GB card: the full 262k window, drafting at every depth, and the layer

[Mirai S](https://huggingface.co/alesha-pro/Qwen3.8-27B-S-mirai-GGUF) (Qwen3.8-27B-S, trellis codes, ~2.4 bits of
information per weight, 11.17 GB) served on an **RTX 4070 12 GB** with the **full 262,144-token trained window at q8_0
KV cache**, MTP speculative decoding from the GGUF's own draft block at every depth, harness-proofing for the apps
that send `effort: "high"` or tiny output caps, and an optional server-side layer (exact API cards, an API check, a
sandboxed Python tool). Same weights as published; every kernel checked greedy token-for-token against the model's
own llama.cpp fork before anything else was measured.

| RTX 4070 12 GB, served, one slot | the model's own fork (`alesha-pro/llama.cpp-mirai-s`) | this serve |
| --- | ---: | ---: |
| context window with q8_0 KV | 64k (11.0 GB) | **262,144** (tiered: 44k positions in VRAM, the rest in pinned RAM) |
| decode, tok/s, at 0 / 16k / 60k / 120k / 180k | 40.0 / 38.1 / 33.5 (60k) / - / - | **75.8 / 71.4 / 40.3 / 16.6 / 10.3** |
| prefill, 16.8k-token prompt | ~1,000 | **1,090** (2048 micro-batch mode: 1,148) |
| speculative decoding | none | MTP draft at every depth, outputs identical to drafting off |
| HumanEval 164, greedy, tests executed in a sandbox | | **158** at medium or at effort "low"; 154 thinking off |
| long exact-work suite, 37 tasks, raw / behind the layer | 13 / 30 (on the model's fork) | **18 / 28** (12 rescues, 2 losses); coding family 4 / 7 of 12, 6 / 8 at effort "low" |
| apps that send `effort: "high"` | template error on every request | answered (normalized to medium) |

Receipts for every row are in `receipts/mirai-port/` and `bench/`; how each number was obtained, and what did not
work, is in `docs/REPORT.md` and `docs/PREFILL.md`. Numbers are from 2026-10-05/06, GDDR6X at stock clocks, display on
the CPU's integrated GPU (see "Getting more positions into VRAM").

## Quick start (Windows, NVIDIA)

1. Download `mirai-s-bundle-win-x64.zip` from [Releases](../../releases) and unzip into this repo (it fills `bin\`),
   or build it (below). The binaries carry sm_89 machine code (RTX 40) and need only the NVIDIA driver.
2. Put `Qwen3.8-27B-S-mirai.gguf` from [alesha-pro on Hugging Face](https://huggingface.co/alesha-pro/Qwen3.8-27B-S-mirai-GGUF)
   in `models\`. The MTP draft block ships inside that file; nothing is grafted.
3. Optional, once: `layer\fetch_runtime.ps1` downloads the sandbox runtime (CPython 3.12 on WASI, checksummed) and runs
   its isolation canaries. Without it the plain server starts.
4. Serve:

   ```powershell
   .\start-server.ps1
   ```

   OpenAI-compatible API on `http://<host>:8080/v1`, bearer key in `artifacts\api_key.txt` (created on first run).
   The launcher reads free VRAM, keeps a safety margin below the point where Windows demotes a background process's
   memory, and puts as many positions of the 262k cache in VRAM as fit (about 44k headless on this card). It prints
   the line it chose.

## Recommended settings

- **Chat, coding answers, anything behind the layer**: the defaults (medium reasoning, 20k thinking budget, layer on).
- **Coding agents that run their own tools** (Cline, Kilo, OpenHands-style loops against `127.0.0.1:18080`, or the
  layer with `"api_cards": false`): send `reasoning_effort: "low"`, and launch with `MIRAI_EFFORT_ALLOWED=low,medium`
  so the server lets it through. Measured on the suite's coding family, raw: 4 -> 6 of 12 at the same seeds, the MIME
  task 0 -> 4 of 4, HumanEval unchanged at 158/164; the cost is longer tool loops (+31% completion tokens).
- **Tool-heavy agents that want speed over depth**: `chat_template_kwargs: {"enable_thinking": false}` per request
  (HumanEval 154/164 at 0.19x the tokens).

## Knobs (environment variables)

| Variable | Default | |
| --- | --- | --- |
| `MIRAI_CTX` | 262144 | context window |
| `MIRAI_CTK` | q8_0 | K/V cache type |
| `MIRAI_TIER` | 1 | 0 = all-VRAM cache (then a 64k window) |
| `MIRAI_KV_VRAM_CELLS` | auto | pin the VRAM line |
| `MIRAI_VRAM_MARGIN` | 800 headless / 1300 with the display on this card | MiB kept free below the demotion point |
| `MIRAI_SPEC` / `MIRAI_SPEC_DEEP` | 2 / 2 | draft size, and past the VRAM line |
| `MIRAI_DRAFT_WINDOW` | 16384 | rows the draft block keeps |
| `MIRAI_EFFORT` / `MIRAI_EFFORT_ALLOWED` | medium / medium | server default effort; effort words the template sees (others become medium) |
| `MIRAI_THINK` / `MIRAI_THINK_BUDGET` | 1 / 20480 | thinking on; tokens before a forced close |
| `MIRAI_HARNESS_PROOF` | 1 | 0 = pass effort words and output caps through unchanged |
| `MIRAI_PREFILL_PLANES` | ffn | prompt-token numerics: `ffn` (one int8 plane for the FFN matmuls, +18% prefill, KL 0.00028), `2` exact, `1` one plane everywhere |
| `MIRAI_KQ_MASK_PACKED` / `MIRAI_UBATCH` | 1 / 1024 | 1-bit attention mask; micro-batch (2048 = +5.6% prefill for ~570 MiB of VRAM) |
| `MIRAI_LEVELS_MIB` | 128 | level-decode chunk footprint for long prompts |
| `MIRAI_LAYER` | 1 | 0 = no layer |
| `MIRAI_PORT`, `MIRAI_MODEL`, `MIRAI_LOG_FILE` | 8080, auto, none | |

### Getting more positions into VRAM

Every GB of VRAM the desktop does not use is ~30k more q8_0 positions at full speed. Run the display from the CPU's
integrated graphics and set GPU-accelerated apps to it in Windows **Settings > System > Display > Graphics**; the
launcher's margin drops from 1300 to 800 MiB headless.

### Why the VRAM line is ~44k and not more

Mirai keeps 8,220 MiB of weights resident; drafting keeps one 150 MiB snapshot of the recurrent state per unit of
rollback depth (two at the default draft 2) plus ~660 MiB for the draft context. Past the line every step reads the
host tail over PCIe; drafting there is worth 2.2x over no drafting. `MIRAI_SPEC=0` moves the line to ~70k positions
at the cost of the 1.85x below it (`docs/REPORT.md`).

## What is here

| path | what |
| --- | --- |
| `engine/` | submodule: [`professorpalmer/llama.cpp-ada-mirai`](https://github.com/professorpalmer/llama.cpp-ada-mirai). PrismML's llama.cpp fork with the serving patches (tiered KV cache, draft window and tail, reasoning flags, batch-invariant kernels, op timing) and Mirai's codec ported on top (ggml types 90-93, CPU and CUDA kernels, rotation and scale tensors, split attention gate, graph hook), plus the prefill work done here (one-plane FFN prompt numerics, packed 1-bit KQ mask, level-decode chunking). |
| `start-server.ps1` | the launcher: sizes the VRAM line from measured fixed costs, starts the layer in front of llama-server. |
| `tooling/` | `build_engine.bat` (Ninja + pip CUDA 13, sm_89), `install_bin.ps1`, `serve.ps1` / `stop.ps1` (hidden test server, log and PID files). |
| `layer/`, `suite/` | the layer and the long exact-work suite, from [`bonsai-ada-surgery`](https://github.com/professorpalmer/bonsai-ada-surgery) with the changes made here (`layer/ORIGIN.md`). |
| `bench/` | the measurement scripts and every run's scoreboard and results (`ML1`..`ML2f`, `E18`..`E21`, HumanEval arms). |
| `receipts/` | small text receipts cited by the docs: profiles, greedy dumps from the model's fork, probe logs. |
| `templates/bonsai-template.jinja` | the chat template used for every measurement (reasoning_effort, thinking on/off). |
| `docs/REPORT.md`, `docs/PREFILL.md`, `docs/ROADMAP.md` | what was found, the prefill investigation, what is left. |

## Build from source

Windows without the CUDA toolkit (VS 2022 Build Tools C++ workload + NVIDIA's pip wheels):

```powershell
python -m pip install cmake ninja nvidia-cuda-nvcc nvidia-cuda-runtime nvidia-cublas nvidia-cuda-nvrtc
git clone --recurse-submodules https://github.com/professorpalmer/mirai-s-ada
cd mirai-s-ada
tooling\build_engine.bat llama-server      # ~30 min first time
tooling\install_bin.ps1                      # copies the result into bin\ next to the CUDA runtime DLLs
```

Linux: the engine builds like any llama.cpp (`cmake -S engine -B build -DGGML_CUDA=ON`); the flags behind the
numbers are one `llama-server` command line:

```bash
llama-server -m Qwen3.8-27B-S-mirai.gguf -ngl 99 -fa on -c 262144 -np 1 -ctk q8_0 -ctv q8_0 --kv-vram-cells 44000 \
  -b 2048 -ub 1024 --kq-mask-packed \
  --spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-n-max-tail 2 --spec-draft-window 16384 -ctkd q8_0 -ctvd q8_0 \
  --reasoning-effort-allow medium --reasoning-max-tokens-floor 24576 --reasoning-budget 20480 --backend-sampling \
  --chat-template-file templates/bonsai-template.jinja --chat-template-kwargs '{"reasoning_effort":"medium"}' --jinja
```

with `GGML_MIRAI_PREFILL_PLANES=ffn` in the environment. Untested on Linux here.

## Measure it yourself

```powershell
python bench\compare_servers.py --base http://127.0.0.1:18080 --against receipts\mirai-port\stock-greedy-nothink.json   # greedy identity vs the model's fork
bash bench\product_smoke.sh                                   # identity, layer round trip, decode by depth
bash bench\prefill_probe.sh                                   # prefill by prompt length
python suite\run_suite.py --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --out suite-out   # the paired suite
python bench\humaneval_wasi.py --arm medium                    # HumanEval 164, sandbox-scored
python bench\determinism_probe.py                             # same request and seed, seven conditions
```

## Credits

alesha-pro for the model, its codec and the llama.cpp fork it ships with. PrismML for the llama.cpp fork the engine
is built on. sudoingX for the planar activation layout and batch-invariant mode in that fork. MIT for everything here;
the weights are their authors'. Not affiliated with alesha-pro or PrismML.
