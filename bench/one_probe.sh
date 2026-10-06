#!/usr/bin/env bash
# One configuration, one measurement: start the test server hidden, time a 2.4k-token prompt (48 tokens out,
# thinking off), report VRAM, stop. Appends to receipts/mirai-port/one_probe.log.
#   bench/one_probe.sh LABEL CTX "EXTRA FLAGS" ["SERVER ENV"]
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/one_probe.log"
LABEL=$1; CTX=$2; EXTRA=$3; SENV=${4:-}
start_server "$LABEL" "$CTX" "$EXTRA" "$SENV" | tee -a "$LOG" || { stop_server; exit 1; }
PYTHONUTF8=1 python - "$(key)" "$BASE" "$LABEL" <<'PY' | tee -a "$LOG"
import json, urllib.request, sys
K, base, label = sys.argv[1], sys.argv[2], sys.argv[3]
prompt = "Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{i%97} note" for i in range(300))
body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 48, "temperature": 0,
        "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
r = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
    {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
tm = r.get("timings") or {}
print(f"{label}: prompt {tm.get('prompt_n')} tok at {tm.get('prompt_per_second'):.0f} tok/s, decode {tm.get('predicted_per_second'):.1f} tok/s "
      f"({tm.get('predicted_n')} tok), draft_n={tm.get('draft_n')} accepted={tm.get('draft_n_accepted')}", flush=True)
PY
echo "$LABEL vram_peak_now=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
stop_server >/dev/null
