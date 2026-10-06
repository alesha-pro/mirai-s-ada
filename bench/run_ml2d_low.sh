#!/usr/bin/env bash
# ML2d-low (DECISIONS 2026-10-05 19:55): the suite's coding + computation families, both arms (raw :18080 vs layer
# :8080) on the product serve as it runs (defaults), every request at reasoning_effort "low" (--effort low on the
# runner). Paired against ML2b (same items and seeds, effort medium). Output: bench/ML2d-low. ~3.5 h.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/ml2d_low.log"
echo "=== ML2d-low $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
curl -s -m 5 http://127.0.0.1:18080/health | tee -a "$LOG"; echo | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding_computation.json" --out "$ROOT/bench/ML2d-low" --label-a mirai-raw --label-b mirai-layer --effort low 2>&1 | tail -12 | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/bench/compare_runs.py" "$ROOT/bench/ML2b" "$ROOT/bench/ML2d-low" 2>&1 | grep -E "coding|computation|rescues|total" | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
