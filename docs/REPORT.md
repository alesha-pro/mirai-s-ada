# Mirai S on a 12 GB card: report

Running notes, newest at the bottom. Method: paired runs, frozen plans and gates in `DECISIONS.md`, receipts in
`receipts/`. Numbers are from this RTX 4070 12 GB unless marked as someone else's.

## 1. The model

`alesha-pro/Qwen3.8-27B-S-mirai-GGUF` (sha256 5aa4365c...), 11.17 GB. Qwen3.8-27B-S weights in four trellis-coded
ggml types (`MS_V4T8`, `MS_V2T4`, `MS_V2T6`, `MS_I3`, ids 90-93 in the engine), about 2.4 bits of information per
weight; model-wide rotation tensors (`mirai.rot.*`), a head auxiliary tensor (`mirai.head_aux`), a split attention
gate, and the MTP draft block (`blk.64`) in Q8_0 inside the same file.

## 2. The records (stock fork, this card)

Mirai's own fork (`alesha-pro/llama.cpp-mirai-s`, upstream d834d44e6), 64k q8 window, 11.0 GB: decode 40.0 / 39.6 /
38.1 / 36.1 / 33.5 tok/s at depth 0 / 4k / 16k / 32k / 60k; prefill ~1000 tok/s at 4k falling to 600 at 60k. No
tiered KV, no speculative decoding, no reasoning budget (`receipts/mirai-port/profile-stock-fork-q8-64k.txt`).

## 3. The port

Mirai's codec (39 files, +3.2k lines over upstream) was merged onto our engine at the pinned product commit of the serving stack
(PrismML llama.cpp + 36 serve patches), not the other way round: eleven hand merges, their GDN / flash-attention /
server changes not taken because ours cover the same ground. One missed CUDA `supports_op` case first put all 417
Mirai tensors in system RAM; fixed, the whole model sits on the GPU at the stock footprint.

Verification: greedy, token-for-token against the stock fork's dumped outputs on five prompts, thinking off (200
tokens) and on (300 tokens): identical on all ten. Speed, plain 64k q8 window: 41.1 / 38.9 / 37.2 / 34.4 tok/s at
0 / 16k / 32k / 60k, +3% over the stock fork from our attention and GDN kernels; nothing Mirai-specific was tuned.

## 4. MTP speculation, and the prefill collapse that was really a VRAM budget

Drafting on the GGUF's Q8_0 MTP block with the stack's recipe (draft 2, q8 draft KV, 16k draft window, tail 4,
backend sampling): outputs identical to the stock dump 5/5, **73.9 tok/s at depth 0** (1.8x). Prompt processing
collapsed to ~50 tok/s against ~930 plain.

The probe (`receipts/mirai-port/prefill_probe.log`): no MTP flag combination mattered (51 tok/s with any of them at
`-b 1024 -ub 1024`), the product batch `-b 2048 -ub 512` gave 746, and the per-op GPU table
(`op-timing-mtp-ub1024.txt`) charged 44 of the 47 s to the trellis matmuls at 1024 columns, the same ops that run
the whole prompt in 2.6 s without MTP. The accounting (`vram-accounting-mtp-64k.txt`) explains it: Mirai keeps
8,220 MiB of weights resident (its 2.4 GB F16 token embedding stays in host RAM), the 64k q8 KV takes 2,176 MiB, the
recurrent state 449, the compute buffer 406, and the MTP draft context another 440; the engine's own fit check at
launch reported 11,691 MiB projected against 10,656 free. Windows demotes the newest allocations to system memory and
prefill is where the big GEMMs touch them. Confirmation: the identical configuration at a 32k window prefills at
887 tok/s with the same draft acceptance (`one_probe.log`, V1). ub512 only slips under the demotion line.

What this means for Mirai S on 12 GB: the resident weights leave about 1.1-1.4 GB for KV in VRAM once the draft
and compute buffers are counted. The tiered KV cache is therefore not only the way to the 262k
window; it is what makes MTP fit at all. The product recipe is built on that budget (section 5, feature tests A/B/C).

## 5. The serving stack on Mirai S: feature tests A, B, C

All on the engine built in this repo, `-b 2048 -ub 512`, q8_0 K/V, greedy identity against the stock fork's dump
checked first in every arm (5/5 each time). `receipts/mirai-port/feature_tests.log`.

| arm | window | VRAM at load | decode tok/s by depth |
| --- | --- | ---: | --- |
| plain (reference) | 64k all-VRAM | 10.7 GB | 41.1 / 38.9 / 37.2 / 34.4 at 0 / 16k / 32k / 60k |
| A: MTP draft 2 | 64k all-VRAM | 11.7 GB | **76.9 / 72.4 / 68.5 / 65.4** (1.85x throughout) |
| B: tiered KV, 32k cells in VRAM | 262,144 | 10.1 GB | 41.0 / 37.2 / **14.6 / 6.2** at 0 / 32k / 60k / 120k |
| C: B + MTP (tail draft 4) | 262,144 | 11.3 GB | **77.0 / 67.9 / 38.7 / 19.5 / 12.6** at 0 / 32k / 60k / 120k / 180k |

The arithmetic behind B: a q8_0 K/V cell for this architecture is 34,816 bytes (16 attention layers, K+V, 4 heads x
256). Mirai keeps 8,220 MiB of weights resident, so the line sits
positions, Mirai's sits at ~32k with drafting (~70k without); past it every step reads the host tail over PCIe (27k
rows, 0.9 GB, at 60k; 87k rows, 3 GB, at 120k), which is B's 14.6 and 6.2. The tail draft in C turns that into 2.65x:
a PCIe-bound step reads the tail once per verify batch, so the extra draft columns cost almost nothing. 38.7 tok/s at
60k in the 262k window beats the plain 64k window's 34.4 at the same depth.

Measured fixed VRAM cost against idle free VRAM (what the launcher's auto-sizing uses): 8,220 MiB without drafting,
9,434 MiB with the MTP draft context. The draft context's 1,214 MiB is the largest leftover on this card: its K/V is
44 MiB; the rest is a second context's compute buffer and pools.

Product defaults (`start-server.ps1`): arm C plus harness-proofing and the layer. `MIRAI_SPEC=0` is the long-context
mode (line at ~70k, no drafting).

### 5b. Where the draft's VRAM really was, and the tail-draft trade (night of 10-04/05)

With a pool-growth log in the engine and `-lv 5` launches (`receipts/mirai-port/vram_split.log`), the MTP draft
context costs 175 MiB (K/V 43, compute 118, pool 14); sharing the transient pool between the two contexts and
halving the draft's micro-batch return 74 MiB together (identity 5/5, decode unchanged) and stay env options under
the 150 MiB gate. The number that mattered is the recurrent-state buffer: 149.6 MiB without speculation, and one
full snapshot per unit of rollback depth with it (449 MiB at draft 2, 748 at the tail draft 4), because a partly
accepted draft has to roll the GDN state back. Each unit is ~4.5k K/V positions.

The tail draft past the VRAM line, measured at 31,488 cells (`tail_draft.log`): tail 2 / 3 / 4 = 32.2 / 37.0 /
38.8 tok/s at 60k and 15.1 / 17.8 / 19.3 at 120k, against 14.6 / 6.2 with no draft, for 449 / 598 / 748 MiB of
snapshots. The product takes tail 2: drafting then costs only the two snapshots it needs below the line, and the
300 MiB returned move the line up ~9k positions where decode is ~70 instead of ~35; past the line it gives up 17%.
With the launcher's fixed-cost model corrected to 8,220 + 150 x depth + 664 MiB (the second context's full cost,
measured), the serve sizes the line to 39,424 positions at the 1,000 MiB margin and measures 75.6 / 71.3 / 37.0 /
16.1 / 10.1 tok/s at 0 / 16k / 60k / 120k / 180k, identity 5/5, the layer's tool round correct
(`product_smoke.log`, 02:11). One launch in between ran with a wrong constant (50,688 cells, ~550 MiB headroom);
its receipts are kept and marked as over budget, not cited.

## 6. The layer in front of Mirai S (ML1, on the stock fork)

The suite paired, 74 runs, raw vs behind the layer with shipped defaults:

| | Mirai S raw | Mirai S + layer |
| --- | ---: | ---: |
| suite, 37 items | 13 | **30** |
| rescues / losses | | 17 / 0 |
| tokens | 488k | 381k (0.78x) |

The layer's three levers (exact API cards, the sandboxed tool with the user's text as a file, the verify sentence)
are model-agnostic: the same families move for the same reasons on both models, workspace passes through
byte-identical on both, and no pair got worse. Cross-model totals are not a ranking (Mirai's fork has no reasoning
budget, so its raw arm can think to the cap without answering); the within-model pairs are the result. Scoreboard
and traces: `bench/ML1/`. Card: `docs/img/mirai-layer.png`.

## 6b. The layer on the product serve (ML2)

Same 37 items and seeds as ML1, paired raw vs layer on this engine with the product defaults (262k tiered window,
MTP, reasoning budget 20,480 with forced close, harness-proofing), 74 runs in 3.5 h:

| | raw | layer | rescues / losses | tokens |
| --- | ---: | ---: | --- | ---: |
| ML1 (stock fork, no reasoning budget) | 13/37 | 30/37 | 17 / 0 | 488k -> 381k |
| ML2 (this serve) | **16/37** | **29/37** | **13 / 0** | 486k -> 377k |

Per family on this serve: coding 3 -> 6 of 12 (tar 0 -> 2, ZIP 3 -> 4, MIME 0 -> 0), computation 5 -> 15 of 15,
workspace 8 -> 8 of 10 (byte-identical passthrough). The raw arm's +3 over ML1 is the serve, not the model: the
forced close turns runs that thought to the cap into answers. The layer's levers stack the same way on both serves.
Served receipt over the run's 525 requests (`receipts/mirai-port/served-ml2.md`): decode median 74.4 tok/s,
prompt median 700 tok/s, draft acceptance 83.5% pooled over 710k drafted tokens.

### 6c. ML2b: the same suite on the prefill work of 10-05

The suite was re-paired on the serve as it stands after the prefill day (one-plane FFN activations for prompt
tokens, packed 1-bit mask, 1024 micro-batch, VRAM line 44,288), same items and seeds, 74 runs in 3.6 h
(`bench/ML2b`, `receipts/mirai-port/ml2-vs-ml2b.md`):

| | raw | layer | rescues / losses | tokens |
| --- | ---: | ---: | --- | ---: |
| ML2 (10-04 defaults) | 16/37 | 29/37 | 13 / 0 | 486k -> 377k |
| ML2b (10-05 defaults) | **18/37** | **28/37** | **12 / 2** | 508k -> 394k |

Per family (raw / layer): coding 4 / 3 of 12, computation 4 / 15 of 15, workspace 10 / 10 of 10. Against ML2 the
layer total is within the pre-declared band (within 3), computation and workspace reproduce ML2 (11 of the 15
computation traces token-identical, the workspace pairs byte-identical), and the raw arm gained 2. The layer's
coding arm lost 3 (two tar seeds and one ZIP seed went pass -> fail), which is also where the run's 2 within-run
losses sit; the failed traces are the test-harness loop seen before, on the long tool-looped prompts that the
one-plane path touches. The pre-registered rule keeps the one-plane default; the coding-only control on the exact
two-plane numerics (`bench/ML2c-coding`, 24 runs) came back layer 4/12, raw 3/12, with six runs moving three each
way against ML2b, so the coding swing is seed noise on long tool-looped prompts and not the prefill numerics
(DECISIONS 2026-10-05 18:15). Served
receipt over the run's 481 requests (`served-ml2b.md`): decode median 73.9 tok/s, prompt median 911 tok/s (700 in
ML2), acceptance 82.8% pooled.

## 6d. Night of 10-05/06: the layer's coding gaps, effort "low", and what the suite can resolve

Five runs on the product serve (`DECISIONS.md` 2026-10-05 21:10 through 2026-10-06 07:15), all plans and gates frozen
before results:

| run | what | result |
| --- | --- | --- |
| E18 | the API check now flags names looked up on a class or called on a fresh stdlib instance (`EmailMessage.from_bytes`, the most repeated MIME mistake, was never flagged before); MIME requests get the `email`, `email.policy`, `email.parser` cards | layer coding 4/12 -> **7/12** (tar 1 -> 3, ZIP 3 -> 4), MIME 0/4 -> 0/4: the pre-registered MIME gate missed, the change kept on no-regression grounds, no MIME claim |
| E19 | a round-countdown note on tool results from the 8th round | 7/12, identical to E18; the model reads the note ("1 response remains... I need to wrap this up") and spends the last response on a tool call anyway; off |
| ML2e-low | coding + computation, both arms, effort "low" (server allow-list verified on the process) | raw 8 -> **12**/27 (MIME 0 -> 4/4), layer 18 -> **23**/27 (coding 3 -> 8 with E18 riding along; computation 15/15 both); tokens +31% raw, +13% layer; medium stays the default, "low" for raw coding agents |
| E20 | MIME at low through the layer with cards off, then lint only | 0/4, then 2/4 (raw 4/4): the cards are not the cause alone; the finish sentence accounts for part; the full-layer prompt makes the first response 2.6x longer on this item (23,382 vs 8,948 tokens) |
| ML2f | second seed set (5-8) for the coding family at medium | layer 5/12, raw 3/12: over both seed sets layer **12/24**, raw 7/24 (tar 1 -> 5 of 8, ZIP 6 -> 7, MIME 0 -> 0) |
| E21 | the finish sentence on Mirai S (coding x12 at medium without it; MIME x4 at low without it, cards on) | 4/12 vs 7/12 with it: the sentence helps here and stays; MIME 0/4 either way at every setting except raw at low (4/4) |
| determinism probe | same request and seed, seven cache/sampling conditions, the layer path, and E18 vs E19 first turns | identical in every condition; 11 of 12 suite first turns byte-identical; one late divergence 35k characters into a 75k response. 4-seed deltas of 1 to 2 are noise; the paired design stands |

ML2d-low (meant as the "low" run) was a medium replay because the launcher's harness-proofing normalized the effort
word; it reproduced ML2b on 54 of 54 runs and is kept as that receipt. Lesson applied: a runner flag the server can
normalize is checked against the server's own setting before a run.

## 7. Open

1. MTP prefill collapse (section 4).
2. Tiered KV on Mirai: VRAM line, decode by depth, identity (section 5).
3. Product recipe on this engine: reasoning budget and harness flags measured on Mirai (they were tuned on the stack's previous model),
   then the suite re-paired on this engine (ML1 was the stock fork) and AppWorld raw.
4. Beyond serving: the MTP block's acceptance rate on Mirai (on the stack's previous model an on-policy head gave
   +4.3 pp); KV precision at depth (KL by position, as done before on this stack); whether any of the model's own translation
   layers (trellis decode kernels, the head's aux path) leave speed on the table at batch 1 and at prefill width.
