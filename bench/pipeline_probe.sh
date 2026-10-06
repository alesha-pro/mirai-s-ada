#!/usr/bin/env bash
# Pipelined long-input path (DECISIONS 2026-10-05 17:xx): level decode + combine on a second stream against the GEMM.
# Arms at the product configuration (ffn planes, packed mask, ub1024, 40,960 cells): pipeline off vs on, at level
# chunk sizes 16 / 32 / 64 MiB; 16.8k prompt twice per arm; then greedy identity (3 long prompts) on the pipelined
# default against the serial path's dump. Output: receipts/mirai-port/pipeline_probe.log
#   BIN=build\bin (default) runs the freshly built tree without touching bin\; set BIN=bin after install.
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/pipeline_probe.log"
export MIRAI_BIN="${BIN:-build\\bin}"
PF="-b 2048 -ub 1024 --kq-mask-packed --kv-vram-cells 40960 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling"
pf() { PYTHONUTF8=1 python - "$(key)" "$BASE" <<'PY'
import json, urllib.request, sys
K, base = sys.argv[1], sys.argv[2]
out = []
for rep in range(2):
    prompt = f"Run {rep}. Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{(i*7+rep)%97} note" for i in range(2000))
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 16, "temperature": 0, "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
    o = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(), {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
    tm = o.get("timings") or {}; out.append(f"{tm.get('prompt_per_second'):.0f}")
print(" / ".join(out) + " tok/s")
PY
}
stop_server >/dev/null; sleep 3
echo "=== pipeline probe $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD) bin=$MIRAI_BIN" | tee -a "$LOG"
# second pass (18:30): LEVELS_MIB now bounds levels + products per chunk, so serial 128 ~ the old 64-MiB levels chunk
ARMS=("$@"); [ ${#ARMS[@]} -eq 0 ] && ARMS=("P0-64 GGML_MIRAI_PIPELINE=0 GGML_MIRAI_LEVELS_MIB=64" "P1-64 GGML_MIRAI_PIPELINE=1 GGML_MIRAI_LEVELS_MIB=64" "P0-128 GGML_MIRAI_PIPELINE=0 GGML_MIRAI_LEVELS_MIB=128" "P1-128 GGML_MIRAI_PIPELINE=1 GGML_MIRAI_LEVELS_MIB=128" "P1-256 GGML_MIRAI_PIPELINE=1 GGML_MIRAI_LEVELS_MIB=256")
for ARM in "${ARMS[@]}"; do
  set -- $ARM; label=$1; shift
  start_server "$label" 262144 "$PF" "GGML_MIRAI_PREFILL_PLANES=ffn $*" | tail -1 | tee -a "$LOG"
  echo "$label ($*) prefill 16.8k: $(pf); vram after $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  if [ "$label" = "P0-64" ]; then
    PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --dump "$ROOT/artifacts/long-serial.json" 2>&1 | tail -1 | tee -a "$LOG"
  elif [ "$label" = "P1-64" ]; then
    echo -n "identity vs serial path: " | tee -a "$LOG"
    PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --against "$ROOT/artifacts/long-serial.json" 2>&1 | tail -1 | tee -a "$LOG"
  fi
  stop_server >/dev/null; sleep 2
done
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
