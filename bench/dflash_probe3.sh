#!/usr/bin/env bash
# E22b: the DFlash drafter with its layers explicitly on the GPU (-ngld 99), drafts 2 / 3 / 4, Q4_0 drafter; same
# measurements as bench/dflash_probe.sh. Output appended to receipts/mirai-port/dflash_probe.log. Restores the product.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/dflash_probe.log"
Q4="$ROOT/models/dflash-Qwen3.8-27B-Q4_0.gguf"; WQ4=$(cygpath -w "$Q4")
COMMON="-b 2048 -ub 1024 --kq-mask-packed --kv-vram-cells 40960 -ctkd q8_0 -ctvd q8_0 --backend-sampling"
stop_server >/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File "$ROOT/tooling/stop.ps1" >/dev/null; sleep 3
echo "=== E22c dflash draft 3 with the 16k draft window $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
run_arm() {
  local label=$1 extra=$2
  start_server "$label" 262144 "$COMMON $extra" "GGML_MIRAI_PREFILL_PLANES=ffn" | tail -1 | tee -a "$LOG"
  if ! curl -s -m 3 "$BASE/health" | grep -q ok; then echo "$label: server not healthy; skipping" | tee -a "$LOG"; stop_server >/dev/null; sleep 2; return; fi
  echo "$label vram at load: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  echo -n "$label identity vs greedy dump: " | tee -a "$LOG"
  PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --against "$ROOT/artifacts/long-serial.json" 2>&1 | tail -1 | tee -a "$LOG"
  for d in 0 16000; do echo -n "$label decode at $d: " | tee -a "$LOG"; PYTHONUTF8=1 python "$ROOT/bench/quick_tps.py" --base "$BASE" --key-file "$ROOT/artifacts/api_key.txt" --depth $d 2>&1 | tail -1 | tee -a "$LOG"; done
  echo -n "$label acceptance: " | tee -a "$LOG"; PYTHONUTF8=1 python "$ROOT/bench/served_receipt.py" "$ROOT/logs/$label.log" 2>/dev/null | grep -E "pooled acceptance|mean draft len" | tr '\n' ' ' | tee -a "$LOG"; echo | tee -a "$LOG"
  echo "$label vram after: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  stop_server >/dev/null; sleep 3
}

run_arm DF3W "--spec-type draft-dflash -md $WQ4 -ngld 99 --spec-draft-n-max 3 --spec-draft-window 16384 --spec-draft-n-max-tail 3"

bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored" | tee -a "$LOG"
