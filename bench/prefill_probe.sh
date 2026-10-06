#!/usr/bin/env bash
# Why is prefill ~45 tok/s with MTP drafting on (vs ~1000 plain)? Restart the test server per variant and time a
# 2.4k-token prompt (48 output tokens, thinking off). P5 repeats the bare MTP config with the per-node GPU timer
# (GGML_CUDA_OP_TIMING=1, CUDA graphs off) so logs/P5.log holds the op breakdown. Output: receipts/mirai-port/prefill_probe.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/prefill_probe.log"; : > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }
probe() { PYTHONUTF8=1 python - "$(key)" "$BASE" "$1" "${2:-48}" <<'PY' | tee -a "$LOG"
import json, urllib.request, sys
K, base, label, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
prompt = "Summarize the following notes in one sentence.\n\n" + " ".join(f"item{i} value{i%97} note" for i in range(300))
body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": n, "temperature": 0,
        "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
r = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
    {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
tm = r.get("timings") or {}
print(f"{label}: prompt {tm.get('prompt_n')} tok at {tm.get('prompt_per_second'):.0f} tok/s, decode {tm.get('predicted_per_second'):.1f} tok/s "
      f"({tm.get('predicted_n')} tok), draft_n={tm.get('draft_n')} accepted={tm.get('draft_n_accepted')}", flush=True)
PY
}
MTP="--spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0"
say "=== prefill probe $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)"
start_server P0 65536 ""                                                                              | tee -a "$LOG"; probe "P0 no MTP (b1024 ub1024)"
start_server P1 65536 "$MTP"                                                                          | tee -a "$LOG"; probe "P1 MTP, no window/tail flags"
start_server P2 65536 "$MTP --spec-draft-window 16384 --spec-draft-n-max-tail 4"                      | tee -a "$LOG"; probe "P2 MTP + window 16384 + tail 4"
start_server P3 65536 "$MTP --spec-draft-window 16384 --spec-draft-n-max-tail 4 --backend-sampling"   | tee -a "$LOG"; probe "P3 + backend-sampling (the A config)"
start_server P4 65536 "$MTP --spec-draft-window 16384 --spec-draft-n-max-tail 4 --backend-sampling -b 2048 -ub 512" | tee -a "$LOG"; probe "P4 A config with b2048 ub512 (product batch)"
start_server P5 65536 "$MTP" "GGML_CUDA_OP_TIMING=1 GGML_CUDA_DISABLE_GRAPHS=1"                       | tee -a "$LOG"; probe "P5 MTP bare, op timing on (graphs off)" 160; probe "P5 again" 160
stop_server | tee -a "$LOG"
say "=== probe done $(date '+%H:%M'); op timing table: logs/P5.log"
