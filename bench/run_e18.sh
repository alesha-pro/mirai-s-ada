#!/usr/bin/env bash
# E18 (DECISIONS 2026-10-05 21:10): coding family, layer arm only, after the apilint class-attribute fix and the email
# parsing cards. Restarts the product (so the layer process picks up the edited modules), runs 12 seeds through
# :8080, compares with ML2c-coding's layer arm. Output: bench/E18-coding-layer, receipts/mirai-port/e18.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/e18.log"
echo "=== E18 $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD) layer $(cd "$ROOT" && git rev-parse --short HEAD)" | tee -a "$LOG"
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_e18.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_e18.log" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding.json" --out "$ROOT/bench/E18-coding-layer" --label-a mirai-layer 2>&1 | tail -8 | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
