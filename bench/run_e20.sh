#!/usr/bin/env bash
# E20 (DECISIONS 2026-10-06 02:10): is it the API cards that sink the layer on MIME at effort "low"? Product restarted
# with MIRAI_EFFORT_ALLOWED=low,medium; MIME 4 seeds through the layer at --effort low in two arms: (a) api_cards off,
# (b) api_cards and finish_note off (lint only). Compared with ML2e-low's MIME rows (raw 4/4, layer 0/4). Product
# restored with defaults at the end. Output: bench/E20-mime-nocards, bench/E20-mime-lintonly, receipts/mirai-port/e20.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/e20.log"
echo "=== E20 $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD) layer $(cd "$ROOT" && git rev-parse --short HEAD)" | tee -a "$LOG"
MIRAI_EFFORT_ALLOWED=low,medium bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_e20.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_e20.log" | tee -a "$LOG"
powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='llama-server.exe'\").CommandLine" | grep -o -E "reasoning-effort-allow [a-z,]+" | tee -a "$LOG"
for ARM in "E20-mime-nocards {\"api_cards\":false}" "E20-mime-lintonly {\"api_cards\":false,\"finish_note\":false}"; do
  set -- $ARM; out=$1; extra=$2
  echo "--- $out $(date '+%H:%M') extra $extra" | tee -a "$LOG"
  PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
      --plan "$ROOT/bench/plans/mime.json" --out "$ROOT/bench/$out" --label-a mirai-layer --effort low --extra-json "$extra" 2>&1 | grep -E "mime|total|tokens" | tee -a "$LOG"
done
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored with defaults" | tee -a "$LOG"
