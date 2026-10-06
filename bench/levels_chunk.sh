#!/usr/bin/env bash
# Level-decode chunk size vs prefill (docs/PREFILL.md item 4 prelude). The long-input path decodes trellis weights to
# int8 levels in chunks of GGML_MIRAI_LEVELS_MIB (default 32) and cuBLASLt reads them back; a chunk that fits the
# 4070's 36 MB L2 together with the activation planes could keep the read on-chip. Product configuration otherwise
# (packed mask, ub1024, ffn planes, 40,960 cells). Output: receipts/mirai-port/levels_chunk.log
#   bench/levels_chunk.sh [MiB values...]   (default: 32 8 16 24 64); LEVELS_MMA=1 adds the MMA1024 arm (done 16:01: 760 tok/s)
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/levels_chunk.log"
PF="-b 2048 -ub 1024 --kq-mask-packed --kv-vram-cells 40960 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling"
pf() { PYTHONUTF8=1 python - "$(key)" "$BASE" <<'PY'
import json, urllib.request, sys
K, base = sys.argv[1], sys.argv[2]
out = []
for rep in range(2):
    prompt = f"Run {rep}. Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{(i*7+rep)%97} note" for i in range(2000))
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 16, "temperature": 0, "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
    o = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(), {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
    tm = o.get("timings") or {}; out.append(f"{tm.get('prompt_per_second'):.0f}")
print(" / ".join(out) + " tok/s")
PY
}
stop_server >/dev/null; sleep 3
echo "=== levels chunk $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
SIZES=("$@"); [ ${#SIZES[@]} -eq 0 ] && SIZES=(32 8 16 24 64)
for M in "${SIZES[@]}"; do
  start_server L$M 262144 "$PF" "GGML_MIRAI_PREFILL_PLANES=ffn GGML_MIRAI_LEVELS_MIB=$M" | tail -1 | tee -a "$LOG"
  echo "L$M (chunk $M MiB) prefill 16.8k: $(pf); vram after $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
done
# the in-register tensor-core path for the whole micro-batch (no level materialization; re-decodes per 64-token tile)
if [ "${LEVELS_MMA:-0}" = 1 ]; then
start_server MMA1024 262144 "$PF" "GGML_MIRAI_PREFILL_PLANES=ffn GGML_MIRAI_MMA_TOKENS=1024" | tail -1 | tee -a "$LOG"
echo "MMA1024 (mma path up to 1024 tokens) prefill 16.8k: $(pf); vram after $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
fi
stop_server >/dev/null
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
