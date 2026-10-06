#!/usr/bin/env bash
# E21 (DECISIONS 2026-10-06 08:10): the finish sentence on Mirai S. (a) coding x12 at medium through the layer with
# finish_note off (vs E18); (b) MIME x4 at low with finish_note off, cards on (vs E20). Product restored after.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/e21.log"
echo "=== E21 $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD) layer $(cd "$ROOT" && git rev-parse --short HEAD)" | tee -a "$LOG"
echo "--- (a) coding x12, medium, finish_note off $(date '+%H:%M')" | tee -a "$LOG"
powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='llama-server.exe'\").CommandLine" | grep -o -E "reasoning-effort-allow [a-z,]+" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/coding.json" --out "$ROOT/bench/E21a-coding-nofinish" --label-a mirai-layer --extra-json '{"finish_note":false}' 2>&1 | grep -E "coding|total|tokens" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/bench/compare_runs.py" "$ROOT/bench/E18-coding-layer" "$ROOT/bench/E21a-coding-nofinish" 2>&1 | grep -E "total|moved" | tail -4 | tee -a "$LOG"
echo "--- (b) MIME x4, low, finish_note off, cards on $(date '+%H:%M')" | tee -a "$LOG"
MIRAI_EFFORT_ALLOWED=low,medium bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_e21.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_e21.log" | tee -a "$LOG"
powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name='llama-server.exe'\").CommandLine" | grep -o -E "reasoning-effort-allow [a-z,]+" | tee -a "$LOG"
PYTHONUTF8=1 python "$ROOT/suite/run_suite.py" --base http://127.0.0.1:8080 --key-file "$ROOT/artifacts/api_key.txt" --model mirai-s-27b \
    --plan "$ROOT/bench/plans/mime.json" --out "$ROOT/bench/E21b-mime-low-nofinish" --label-a mirai-layer --effort low --extra-json '{"finish_note":false}' 2>&1 | grep -E "mime|total|tokens" | tee -a "$LOG"
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored with defaults" | tee -a "$LOG"
