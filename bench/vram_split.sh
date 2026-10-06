#!/usr/bin/env bash
# Where does the MTP draft context's VRAM go? (docs/ROADMAP.md item 1.) Launch the product configuration as a test
# server at -lv 5 and read nvidia-smi at four points: after load without warmup (static buffers), after one
# 1-token request (pools + CUDA graphs), after a 2.4k prompt (prefill high-water), then the same with CUDA graphs
# disabled (graph instances' share). The server log carries both contexts' buffer lines and, with the engine's
# pool-growth log, each backend instance's pool high-water. Output: receipts/mirai-port/vram_split.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/vram_split.log"
PROD="-b 2048 -ub 512 --kv-vram-cells 31488 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 4 --backend-sampling --no-warmup -lv 5"
vram() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 | tr -d ' '; }
req() { # N_TOKENS PROMPT_ITEMS
  PYTHONUTF8=1 python - "$(key)" "$BASE" "$1" "$2" <<'PY'
import json, urllib.request, sys
K, base, n, items = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
prompt = "Summarize in one sentence.\n\n" + " ".join(f"item{i} value{i%97} note" for i in range(items)) if items else "Say hi."
body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": n, "temperature": 0, "cache_prompt": False,
        "chat_template_kwargs": {"enable_thinking": False}}
r = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
    {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
tm = r.get("timings") or {}
print(f"prompt {tm.get('prompt_n')} tok at {tm.get('prompt_per_second') or 0:.0f} tok/s, decode {tm.get('predicted_per_second') or 0:.1f}", end="")
PY
}
run() { # LABEL "SERVER ENV"
  start_server "$1" 262144 "$PROD" "$2" | tee -a "$LOG" || return 1
  echo "$1 after load (no warmup): $(vram) MiB" | tee -a "$LOG"
  echo "$1 after 1 token ($(req 1 0)): $(vram) MiB" | tee -a "$LOG"
  echo "$1 after 2.4k prompt ($(req 32 300)): $(vram) MiB" | tee -a "$LOG"
  echo "$1 after 32 more tokens ($(req 32 0)): $(vram) MiB" | tee -a "$LOG"
  echo "$1 buffer lines:" | tee -a "$LOG"
  sed 's/\x1b\[[0-9;]*m//g' "$ROOT/logs/$1.log" | grep -E "compute buffer size|KV buffer size|RS buffer size|model buffer size|pool\[|draft context sized" | cut -c14-150 | tee -a "$LOG"
}
echo "=== vram split $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD); idle $(vram) MiB" | tee -a "$LOG"
run G1 "GGML_CUDA_POOL_LOG=1"                                                  # product as is
run G0 "GGML_CUDA_POOL_LOG=1 GGML_CUDA_DISABLE_GRAPHS=1"                        # graphs off: the graph instances' share
run G2 "GGML_CUDA_POOL_LOG=1 GGML_CUDA_SHARED_POOL=1"                           # one transient pool for both contexts
run G3 "GGML_CUDA_POOL_LOG=1 LLAMA_MTP_DRAFT_UBATCH=256"                        # smaller draft compute buffer
run G4 "GGML_CUDA_POOL_LOG=1 GGML_CUDA_SHARED_POOL=1 LLAMA_MTP_DRAFT_UBATCH=256" # both
echo "G4 greedy-identical (thinking off): $(greedy_identity stock-greedy-nothink.json)" | tee -a "$LOG"
for d in 0 16000 32000; do echo "G4 depth $d: $(tps_at $d)" | tee -a "$LOG"; done
stop_server | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
