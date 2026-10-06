#!/usr/bin/env bash
# ML2e-low (DECISIONS 2026-10-05 23:30): ML2d-low done right. The product is restarted with MIRAI_EFFORT_ALLOWED=low,medium
# so the runner's --effort low reaches the template; coding + computation, both arms; then the product is restored
# with its defaults. Output: bench/ML2e-low, receipts/mirai-port/ml2e_low.log. ~2.5 h.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/ml2e_low.log"
echo "=== ML2e-low $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
MIRAI_EFFORT_ALLOWED=low,medium bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_ml2e.log" 2>&1
grep -E "inner health|layer health|^listen|effort" "$ROOT/logs/product_ml2e.log" "$ROOT/logs/product.launcher.log" 2>/dev/null | grep -i "allow\|listen\|health" | tail -3 | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding_computation.json" --out "$ROOT/bench/ML2e-low" --label-a mirai-raw --label-b mirai-layer --effort low 2>&1 | tail -12 | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/bench/compare_runs.py" "$ROOT/bench/ML2b" "$ROOT/bench/ML2e-low" 2>&1 | grep -E "coding|computation|rescues|total|moved" | tail -8 | tee -a "$LOG"
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored with defaults" | tee -a "$LOG"
