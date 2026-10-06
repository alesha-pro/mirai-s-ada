#!/usr/bin/env bash
# Packed (1-bit) KQ mask: identity against the f16 mask on long prompts, compute buffer and VRAM at load, prefill
# at micro-batch 512 and 2048. Product flags otherwise (tiered 262k at 40,960 cells, MTP). Stops the product serve,
# restores it at the end. Output: receipts/mirai-port/mask_packed.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/mask_packed.log"
PF="--kv-vram-cells 40960 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling -lv 5"
buf() { sed 's/\x1b\[[0-9;]*m//g' "$ROOT/logs/$1.log" | grep -E "CUDA0 compute buffer size|CUDA_Host compute buffer size" | head -2 | cut -c14-80 | tr '\n' ';'; }
pf16k() { PYTHONUTF8=1 python - "$(key)" "$BASE" <<'PY'
import json, urllib.request, sys
K, base = sys.argv[1], sys.argv[2]
prompt = "Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{i%97} note" for i in range(2000))
body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 16, "temperature": 0, "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
o = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(), {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
tm = o.get("timings") or {}; print(f"{tm.get('prompt_n')} tok at {tm.get('prompt_per_second'):.0f} tok/s")
PY
}
stop_server >/dev/null; sleep 3
echo "=== packed mask $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
start_server M16 262144 "-b 2048 -ub 512 $PF" "" | tail -1 | tee -a "$LOG"
echo "M16 (f16 mask, ub512) buffers: $(buf M16)  vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --dump "$ROOT/artifacts/long-f16.json" | tee -a "$LOG"
echo "M16 prefill 16k: $(pf16k)" | tee -a "$LOG"
for ub in 512 2048; do
  start_server MP$ub 262144 "-b 2048 -ub $ub --kq-mask-packed $PF" "" | tail -1 | tee -a "$LOG"
  echo "MP$ub (packed, ub$ub) buffers: $(buf MP$ub)  vram $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --against "$ROOT/artifacts/long-f16.json" | tee -a "$LOG"
  echo "MP$ub prefill 16k: $(pf16k)" | tee -a "$LOG"
  echo "MP$ub vram after: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
done
stop_server >/dev/null
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1; grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
