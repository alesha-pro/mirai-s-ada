#!/usr/bin/env bash
# E19 (DECISIONS 2026-10-06 00:40): the round countdown note, on top of E18's lint and cards. Restarts the product
# with MIRAI_ROUND_NOTE=1, runs the coding family through the layer (12 seeds), compares with E18, restores defaults.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/e19.log"
echo "=== E19 $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD) layer $(cd "$ROOT" && git rev-parse --short HEAD)" | tee -a "$LOG"
MIRAI_ROUND_NOTE=1 bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_e19.log" 2>&1
grep -E "inner health|layer health|layer  on" "$ROOT/logs/product_e19.log" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding.json" --out "$ROOT/bench/E19-coding-layer" --label-a mirai-layer 2>&1 | tail -8 | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/bench/compare_runs.py" "$ROOT/bench/E18-coding-layer" "$ROOT/bench/E19-coding-layer" 2>&1 | grep -E "coding|total|moved" | tail -6 | tee -a "$LOG"
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored with defaults" | tee -a "$LOG"
