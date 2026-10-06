#!/usr/bin/env bash
# ML1: the Bonsai layer in front of Mirai S. Waits for AW2b to finish (its restore brings Bonsai back), then swaps
# to Mirai S on its own fork (:18080), starts the layer (:8080 -> :18080), runs the suite paired (raw vs layer),
# and restores the Bonsai product serve. Logs to ML1.log.
set -u
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
ROOT="C:/Users/pwall/Projects/bonsai-2-27b-serve"
BENCH="$ROOT/artifacts/quality-20260929/bench"
SCRIPTS="$ROOT/artifacts/experiments/spec-ab-20260928"
K=$(tr -d '\r\n' < "$ROOT/artifacts/api_key.txt")
until grep -q "AW2 done" "$BENCH/AW2b.log" 2>/dev/null; do sleep 120; done
echo "== AW2b complete, ML1 starts $(date +%H:%M)"
stop_all() {
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { \$_.CommandLine -match 'bonsai_layer' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }; Get-Process llama-server -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 6"
}
wait_health() {
  powershell -NoProfile -Command "\$ok=\$false; for(\$i=0;\$i -lt 120;\$i++){ Start-Sleep 3; try { if((Invoke-RestMethod -Uri 'http://127.0.0.1:$1/health' -TimeoutSec 3).status -eq 'ok'){ \$ok=\$true; break } } catch {} }; \"health($1)=\$ok\"; \$k=(Get-Content '$ROOT/artifacts/api_key.txt' -Raw).Trim(); try { (Invoke-RestMethod -Uri 'http://127.0.0.1:$1/props' -Headers @{Authorization=\"Bearer \$k\"}).model_path } catch {}"
}
stop_all
powershell -NoProfile -Command "Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File','$SCRIPTS/run-mirai.ps1') | Out-Null"
wait_health 18080
powershell -NoProfile -Command "\$env:BONSAI_LAYER_KEY='$K'; Start-Process python -WindowStyle Hidden -ArgumentList @('$ROOT/layer/bonsai_layer.py','--host','0.0.0.0','--port','8080','--upstream','http://127.0.0.1:18080'); Remove-Item Env:BONSAI_LAYER_KEY; Start-Sleep 4; 'layer ' + (Invoke-RestMethod http://127.0.0.1:8080/health).status"
cd "$ROOT"
python suite/run_suite.py --base http://127.0.0.1:18080 --base-b http://127.0.0.1:8080 --label-a mirai-raw --label-b mirai-layer --out "$BENCH/ML1" 2>&1 | tail -25
echo "== ML1 suite done $(date +%H:%M)"
stop_all
powershell -NoProfile -Command "\$env:GGML_CUDA_BATCH_INVARIANT='1'; Start-Process powershell -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File','$ROOT/start-server.ps1') | Out-Null"
wait_health 8080
echo "== ML1 done, product serve restored $(date +%H:%M)"
