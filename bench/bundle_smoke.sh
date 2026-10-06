#!/usr/bin/env bash
# Clean-folder smoke of the Windows bundle: unzip to a fresh folder, point the launcher at the model and a log file, start
# it hidden with its defaults (layer off: the runtime is not fetched here), wait for health on :8080, run the greedy
# identity check against the stock-fork dump, print the launcher's VRAM line, stop it, restore the product.
#   bench/bundle_smoke.sh artifacts/release/mirai-s-bundle-win-x64-YYYYMMDD.zip
ZIP="$(realpath "${1:?zip path}")"
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/bundle_smoke.log"
SMOKE="$TEMP/mirai-bundle-smoke-$(date +%H%M%S)"; mkdir -p "$SMOKE"
echo "=== bundle smoke $(date '+%F %H:%M') $(basename "$ZIP") $(stat -c %s "$ZIP") bytes" | tee -a "$LOG"
stop_server >/dev/null; powershell -NoProfile -ExecutionPolicy Bypass -File "$ROOT/tooling/stop.ps1" >/dev/null; sleep 3
unzip -q "$ZIP" -d "$SMOKE" && echo "unzipped: $(find "$SMOKE" -type f | wc -l) files; top: $(ls "$SMOKE" | tr '\n' ' ')" | tee -a "$LOG"
WSMOKE=$(cygpath -w "$SMOKE"); WMODEL=$(cygpath -w "$ROOT/models/Qwen3.8-27B-S-mirai.gguf")
MIRAI_MODEL="$WMODEL" MIRAI_LAYER=0 MIRAI_LOG_FILE="$WSMOKE\server.log" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$WSMOKE\start-server.ps1' -RedirectStandardOutput '$WSMOKE\launcher.log'"
ok=0; for i in $(seq 1 120); do sleep 3; curl -s -m 3 http://127.0.0.1:8080/health 2>/dev/null | grep -q '"ok"' && { ok=1; break; }; done
echo "health after $((i*3)) s: $ok" | tee -a "$LOG"; grep -E "^(line|kv|prefill|spec|listen|layer|vram)" "$SMOKE/launcher.log" | tee -a "$LOG"
if [ $ok = 1 ]; then
  KEYF="$SMOKE/artifacts/api_key.txt"; echo "api key created: $([ -f "$KEYF" ] && echo yes || echo NO)" | tee -a "$LOG"
  PYTHONUTF8=1 python "$ROOT/bench/compare_servers.py" --base http://127.0.0.1:8080 --key-file "$KEYF" --against "$ROOT/receipts/mirai-port/stock-greedy-nothink.json" 2>&1 | tail -6 | tee -a "$LOG"
  echo "vram: $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
fi
powershell -NoProfile -ExecutionPolicy Bypass -File "$SMOKE/tooling/stop.ps1" | tail -1 | tee -a "$LOG"
sleep 3; bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored" | tee -a "$LOG"
