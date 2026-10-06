#!/usr/bin/env bash
# ML2 (DECISIONS.md 2026-10-04 21:40): the suite's default frozen plan, 37 items x 2 arms, paired request by request
# against the PRODUCT serve (start-server.ps1 defaults): mirai-raw = llama-server on 127.0.0.1:18080, mirai-layer =
# the layer on :8080. Same seeds as ML1/S1. Output: bench/ML2 (results.jsonl, scoreboard.md, traces/), log logs/ML2.run.log.
# The serve must already be up (bench/product_smoke.sh --start-only). ~6.5 h.
# OUT=bench/ML2b reruns the same plan into another directory (e.g. after a change to the serve).
cd "$(dirname "$0")/.." || exit 1
OUT="${OUT:-bench/ML2}"; NAME="$(basename "$OUT")"
curl -s -m 3 http://127.0.0.1:18080/health | grep -q '"ok"' || { echo "inner server not up"; exit 1; }
curl -s -m 3 http://127.0.0.1:8080/health  | grep -q -i ok    || { echo "layer not up"; exit 1; }
echo "=== $NAME start $(date '+%F %H:%M') engine $(git -C engine rev-parse --short HEAD) layer $(sha256sum layer/bonsai_layer.py | cut -c1-12); serve: $(grep -E '^prefill|^kv' logs/product.launcher.log | tr '\n' ' ')"
PYTHONUTF8=1 python suite/run_suite.py --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 \
    --key-file artifacts/api_key.txt --model mirai-s-27b --out "$OUT" --label-a mirai-raw --label-b mirai-layer
echo "=== $NAME end $(date '+%F %H:%M')"
