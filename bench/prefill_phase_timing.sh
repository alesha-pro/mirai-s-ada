#!/usr/bin/env bash
# Per-phase GPU time of the long-input trellis matmul (GGML_MIRAI_TIMING=1: split / level decode / GEMM / combine),
# one 16k prompt at the product configuration, two planes and the ffn one-plane mode. The engine prints a line every
# 1024 long-input calls through the log (needs -lv 5). Output: receipts/mirai-port/prefill_phase_timing.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/prefill_phase_timing.log"
PF="-b 2048 -ub 512 --kv-vram-cells 40960 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling -lv 5"
echo "=== prefill phase timing $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
for arm in "F2 GGML_MIRAI_TIMING=1" "Fffn GGML_MIRAI_TIMING=1 GGML_MIRAI_PREFILL_PLANES=ffn"; do set -- $arm; label=$1; shift; envs="$*"
  start_server "$label" 262144 "$PF" "$envs" | tail -1 | tee -a "$LOG"
  PYTHONUTF8=1 python - "$(key)" "$BASE" "$label" <<'PY' | tee -a "$LOG"
import json, urllib.request, sys
K, base, label = sys.argv[1], sys.argv[2], sys.argv[3]
prompt = "Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{i%97} note" for i in range(2000))
body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 16, "temperature": 0, "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
o = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(), {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
tm = o.get("timings") or {}
print(f"{label}: prompt {tm.get('prompt_n')} tok at {tm.get('prompt_per_second'):.0f} tok/s (timing sync on, slower than the product)")
PY
  sed 's/\x1b\[[0-9;]*m//g' "$ROOT/logs/$label.log" | grep "mirai prefill timing" | tail -3 | cut -c14-220 | tee -a "$LOG"
done
stop_server >/dev/null
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
