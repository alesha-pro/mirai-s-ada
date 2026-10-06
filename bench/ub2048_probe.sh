#!/usr/bin/env bash
# 2048 micro-batch vs the product's 1024 (DECISIONS 2026-10-05 18:45: halves the per-token level-decode share, costs
# ~310 MiB of compute buffer = ~9,300 q8_0 positions off the VRAM line). Arms at the product configuration (ffn planes,
# packed mask, chunk 128, MTP draft 2 / tail 2): U1024 with 40,960 cells, U2048 with 31,600 cells (the 310 MiB
# paid in positions, so neither arm over-commits). 16.8k prompt twice per arm, VRAM at load and after, greedy identity
# of U2048 against the serial-path dump (artifacts/long-serial.json). Output: receipts/mirai-port/ub2048_probe.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/ub2048_probe.log"
COMMON="--kq-mask-packed --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 2 --backend-sampling"
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
echo "=== ub2048 probe $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
for ARM in "U1024 1024 40960" "U2048 2048 31600"; do
  set -- $ARM; label=$1; ub=$2; cells=$3
  start_server "$label" 262144 "-b 2048 -ub $ub --kv-vram-cells $cells $COMMON" "GGML_MIRAI_PREFILL_PLANES=ffn" | tail -1 | tee -a "$LOG"
  echo "$label (ub $ub, $cells cells) prefill 16.8k: $(pf); vram after $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  if [ "$label" = "U2048" ]; then
    echo -n "U2048 identity vs serial dump: " | tee -a "$LOG"
    PYTHONUTF8=1 python "$ROOT/bench/long_identity.py" --base "$BASE" --against "$ROOT/artifacts/long-serial.json" 2>&1 | tail -1 | tee -a "$LOG"
  fi
  stop_server >/dev/null; sleep 2
done
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
