#!/usr/bin/env bash
# ML2f (DECISIONS 2026-10-06 07:45): second seed set for the coding family, product defaults (medium), raw vs layer
# with E18's lint and cards in the layer. Seeds 5-8 x tar/ZIP/MIME, 24 runs. Output: bench/ML2f-coding-s5-8.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/ml2f.log"
echo "=== ML2f $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD) layer $(cd "$ROOT" && git rev-parse --short HEAD)" | tee -a "$LOG"
powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='llama-server.exe'\").CommandLine" | grep -o -E "reasoning-effort-allow [a-z,]+" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding_s5-8.json" --out "$ROOT/bench/ML2f-coding-s5-8" --label-a mirai-raw --label-b mirai-layer 2>&1 | tail -10 | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
