#!/usr/bin/env bash
# E22 (DECISIONS 2026-10-06 14:10): DFlash drafting (ggml-org dflash-Qwen3.8-27B drafter) vs the GGUF's MTP block on
# Mirai S. Arms at the product configuration (262k tiered, 40,960 cells, packed mask, ub1024, ffn planes):
#   MTP2     --spec-type draft-mtp, draft 2 / tail 2                       (today's product)
#   DF3/5/7  --spec-type draft-dflash -md dflash Q4_0, draft n-max 3 / 5 / 7
#   DF5Q8    the Q8_0 drafter at draft 5
# Per arm: VRAM at load, greedy identity on the long prompts against the no-draft-equivalent dump, decode at depth 0
# and 16k (bench/quick_tps.py), draft acceptance from the arm's log (bench/served_receipt.py), VRAM after.
# Output: receipts/mirai-port/dflash_probe.log. Restores the product at the end.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/dflash_probe.log"
Q4="$ROOT/models/dflash-Qwen3.8-27B-Q4_0.gguf"; Q8="$ROOT/models/dflash-Qwen3.8-27B-Q8_0.gguf"
wait_file() { local f=$1 want=$2; until [ -f "$f" ] && [ "$(stat -c %s "$f")" -ge "$want" ]; do sleep 20; done; }
wait_file "$Q4" 1094000000
COMMON="-b 2048 -ub 1024 --kq-mask-packed --kv-vram-cells 40960 -ctkd q8_0 -ctvd q8_0 --backend-sampling"
WQ4=$(cygpath -w "$Q4"); WQ8=$(cygpath -w "$Q8")
stop_server >/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File "$ROOT/tooling/stop.ps1" >/dev/null; sleep 3
echo "=== E22 dflash probe $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
run_arm() { # LABEL "EXTRA FLAGS"
  local label=$1 extra=$2
  start_server "$label" 262144 "$COMMON $extra" "GGML_MIRAI_PREFILL_PLANES=ffn" | tail -1 | tee -a "$LOG"
  if ! curl -s -m 3 "$BASE/health" | grep -q ok; then echo "$label: server not healthy; skipping" | tee -a "$LOG"; stop_server >/dev/null; sleep 2; return; fi
  echo "$label vram at load: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  echo -n "$label identity vs greedy dump: " | tee -a "$LOG"
  PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --against "$ROOT/artifacts/long-serial.json" 2>&1 | tail -1 | tee -a "$LOG"
  for d in 0 16000; do
    echo -n "$label decode at $d: " | tee -a "$LOG"
    PYTHONUTF8=1 python "$ROOT/bench/quick_tps.py" --base "$BASE" --key-file "$ROOT/artifacts/api_key.txt" --depth $d 2>&1 | tail -1 | tee -a "$LOG"
  done
  echo -n "$label acceptance: " | tee -a "$LOG"
  PYTHONUTF8=1 python "$ROOT/bench/served_receipt.py" "$ROOT/logs/$label.log" 2>/dev/null | grep -E "pooled acceptance|mean draft len" | tr '\n' ' ' | tee -a "$LOG"; echo | tee -a "$LOG"
  echo "$label vram after: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  stop_server >/dev/null; sleep 3
}
run_arm MTP2  "--spec-type draft-mtp --spec-draft-n-max 2 --spec-draft-n-max-tail 2 --spec-draft-window 16384"
run_arm DF3   "--spec-type draft-dflash -md $WQ4 --spec-draft-n-max 3"
run_arm DF5   "--spec-type draft-dflash -md $WQ4 --spec-draft-n-max 5"
run_arm DF7   "--spec-type draft-dflash -md $WQ4 --spec-draft-n-max 7"
if [ -f "$Q8" ] && [ "$(stat -c %s "$Q8")" -ge 2056000000 ]; then run_arm DF5Q8 "--spec-type draft-dflash -md $WQ8 --spec-draft-n-max 5"; else echo "DF5Q8 skipped: Q8 drafter not downloaded yet" | tee -a "$LOG"; fi
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored (today's defaults)" | tee -a "$LOG"
