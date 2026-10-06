#!/usr/bin/env bash
# Prefill vs micro-batch and trellis decode chunk (config only, no engine change). Product flags, tiered 262k with a
# fixed 40,960-cell line (room for larger compute buffers), MTP on. Each arm: VRAM at load, a 16k-token prompt's
# prefill tok/s (two prompts, cache off), compute buffer line. Output: receipts/mirai-port/prefill_tiers.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/prefill_tiers.log"
COMMON="--kv-vram-cells 40960 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling -lv 5"
pf() { PYTHONUTF8=1 python - "$(key)" "$BASE" <<'PY'
import json, urllib.request, sys
K, base = sys.argv[1], sys.argv[2]
r = []
for rep in range(2):
    prompt = f"Run {rep}. Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{(i*7+rep)%97} note" for i in range(2000))
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": 16, "temperature": 0, "cache_prompt": False,
            "chat_template_kwargs": {"enable_thinking": False}}
    o = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
        {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
    tm = o.get("timings") or {}
    r.append((tm.get("prompt_n"), tm.get("prompt_per_second")))
print(" / ".join(f"{n} tok at {p:.0f} tok/s" for n, p in r))
PY
}
echo "=== prefill tiers $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
run() { # LABEL "BATCH FLAGS" "ENV"
  start_server "$1" 262144 "$2 $COMMON" "$3" | tail -1 | tee -a "$LOG"
  echo "$1 prefill: $(pf)" | tee -a "$LOG"
  echo "$1 compute: $(sed 's/\x1b\[[0-9;]*m//g' "$ROOT/logs/$1.log" | grep -E "CUDA0 compute buffer size" | cut -c14-90 | tr '\n' ';')  vram_after=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
}
run U512  "-b 2048 -ub 512"  ""
run U1024 "-b 2048 -ub 1024" ""
run U2048 "-b 2048 -ub 2048" ""
run U1024L "-b 2048 -ub 1024" "GGML_MIRAI_LEVELS_MIB=128"
run U2048L "-b 4096 -ub 2048" "GGML_MIRAI_LEVELS_MIB=128"
stop_server | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
