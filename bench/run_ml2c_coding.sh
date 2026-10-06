#!/usr/bin/env bash
# ML2c-coding (DECISIONS 2026-10-05 16:00): the suite's coding family only, both arms (raw :18080 vs layer :8080), same
# seeds as ML2/ML2b, on the product serve restarted with the EXACT two-plane prefill numerics (MIRAI_PREFILL_PLANES=2);
# packed mask and ub1024 kept (identity-neutral). Isolates the one-plane planes for layer coding workloads.
# Output: bench/ML2c-coding; restores the product with its defaults at the end. ~1.5 h.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/ml2c_coding.log"
echo "=== ML2c-coding $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
MIRAI_PREFILL_PLANES=2 bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_ml2c.log" 2>&1
grep -E "^prefill|inner health|layer health" "$ROOT/logs/product_ml2c.log" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding.json" --out "$ROOT/bench/ML2c-coding" --label-a mirai-raw --label-b mirai-layer 2>&1 | tail -10 | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/bench/compare_runs.py" "$ROOT/bench/ML2b" "$ROOT/bench/ML2c-coding" 2>&1 | grep -E "coding|rescues" | tee -a "$LOG"
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "^prefill|inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored with defaults" | tee -a "$LOG"
