#!/usr/bin/env bash
# One-plane int8 activations for the prefill GEMM (docs/PREFILL.md item 2): KL divergence by token against the
# two-plane path on a local calibration text, plus prefill speed and VRAM. Uses the engine's llama-perplexity
# (--kl-divergence) from bin\. Stops the product serve, restores it at the end.
#   bench/kl_planes.sh [CHUNKS=8] [MODE=1]   (MODE = value of GGML_MIRAI_PREFILL_PLANES for the candidate: 1 or ffn;
#   ctx 2048 per chunk; the base logits file is ~0.5 MB per token and is reused when it exists)
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/kl_planes.log"
CHUNKS=${1:-8}; MODE=${2:-1}
TEXT="$ROOT/artifacts/calib/local-prose.txt"; BASE_KLD="$ROOT/artifacts/calib/two-plane.kld"
MODEL="$ROOT/models/Qwen3.8-27B-S-mirai.gguf"
PPL="$ROOT/bin/llama-perplexity.exe"
COMMON=(-m "$MODEL" -f "$TEXT" -c 2048 --chunks "$CHUNKS" -b 2048 -ub 512 -ngl 99 -fa on -ctk q8_0 -ctv q8_0)
stop_server >/dev/null; sleep 3
echo "=== kl planes $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD); chunks $CHUNKS x 2048 of $(wc -c < "$TEXT") chars" | tee -a "$LOG"
cd "$ROOT/bin" || exit 1
if [ -s "$BASE_KLD" ]; then
  echo "--- base: two planes, reusing $BASE_KLD" | tee -a "$LOG"
else
  echo "--- base: two planes (product numerics), saving logits" | tee -a "$LOG"
  GGML_CUDA_BATCH_INVARIANT=1 "$PPL" "${COMMON[@]}" --kl-divergence-base "$BASE_KLD" 2>&1 | grep -E "Final estimate|^\[|prompt eval|eval time|tokens per second" | tail -4 | tee -a "$LOG"
fi
echo "--- candidate: GGML_MIRAI_PREFILL_PLANES=$MODE, KL against the base" | tee -a "$LOG"
GGML_CUDA_BATCH_INVARIANT=1 GGML_MIRAI_PREFILL_PLANES=$MODE "$PPL" "${COMMON[@]}" --kl-divergence-base "$BASE_KLD" --kl-divergence 2>&1 | grep -E "Mean|KLD|Same top|Maximum|99|95|90|median|PPL|ln\(PPL|RMS" | tail -24 | tee -a "$LOG"
echo "--- control: two planes again, KL against the base (should be ~0; measures the harness floor)" | tee -a "$LOG"
GGML_CUDA_BATCH_INVARIANT=1 "$PPL" "${COMMON[@]}" --kl-divergence-base "$BASE_KLD" --kl-divergence 2>&1 | grep -E "Mean    KLD|Same top p|Maximum KLD|99.9%|99.0%" | tail -6 | tee -a "$LOG"
cd "$ROOT/bench"
echo "--- prefill speed at the product configuration, two planes vs one" | tee -a "$LOG"
PF="-b 2048 -ub 512 --kv-vram-cells 40960 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling"
for arm in "P2 " "P$MODE GGML_MIRAI_PREFILL_PLANES=$MODE"; do set -- $arm; label=$1; envs=${2:-}
  start_server "$label" 262144 "$PF" "$envs" | tail -1 | tee -a "$LOG"
  echo "$label prefill: $(PYTHONUTF8=1 python - "$(key)" "$BASE" <<'PY'
import json, urllib.request, sys
K, base = sys.argv[1], sys.argv[2]
out = []
for rep in range(2):
    prompt = f"Run {rep}. Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{(i*7+rep)%97} note" for i in range(2000))
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 16, "temperature": 0, "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
    o = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(), {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
    tm = o.get("timings") or {}; out.append(f"{tm.get('prompt_n')} tok at {tm.get('prompt_per_second'):.0f} tok/s")
print(" / ".join(out))
PY
)" | tee -a "$LOG"
  echo "$label greedy vs stock dump (thinking off): $(greedy_identity stock-greedy-nothink.json)" | tee -a "$LOG"
done
stop_server >/dev/null
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1; grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
