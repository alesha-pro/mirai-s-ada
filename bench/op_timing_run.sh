#!/usr/bin/env bash
# Per-op GPU time breakdown for one server configuration (GGML_CUDA_OP_TIMING=1, CUDA graphs off; the engine prints
# the top 30 ops every 100 graphs). Runs a 2.4k-token prompt with a long generation so the table prints, then shows
# the first table (prefill-heavy) and the last (decode-heavy).
#   bench/op_timing_run.sh LABEL CTX "EXTRA FLAGS" [N_TOKENS=400] [N_ITEMS=300]   (300 items ~ 2.4k prompt tokens; 2000 ~ 16k)
cd "$(dirname "$0")" && . ./lib.sh
LABEL=$1; CTX=$2; EXTRA=$3; N=${4:-400}; ITEMS=${5:-300}
export MIRAI_CAPTURE_STDERR=1
start_server "$LABEL" "$CTX" "$EXTRA" "GGML_CUDA_OP_TIMING=1 GGML_CUDA_DISABLE_GRAPHS=1" || exit 1
PYTHONUTF8=1 python - "$(key)" "$BASE" "$LABEL" "$N" "$ITEMS" <<'PY'
import json, urllib.request, sys
K, base, label, n, items = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
prompt = "Summarize the following notes in one sentence, then write a 300 word essay about archives.\n\n" + " ".join(f"item{i} value{i%97} note" for i in range(items))
body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": n, "temperature": 0,
        "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
r = json.loads(urllib.request.urlopen(urllib.request.Request(base + "/v1/chat/completions", json.dumps(body).encode(),
    {"Authorization": "Bearer " + K, "Content-Type": "application/json"}), timeout=1800).read())
tm = r.get("timings") or {}
print(f"{label}: prompt {tm.get('prompt_n')} tok at {tm.get('prompt_per_second'):.0f} tok/s, decode {tm.get('predicted_per_second'):.1f} tok/s ({tm.get('predicted_n')} tok)")
PY
stop_server >/dev/null
for f in "$ROOT/logs/$LABEL.stderr" "$ROOT/logs/$LABEL.log"; do
  [ -f "$f" ] || continue
  n=$(sed 's/\x1b\[[0-9;]*m//g' "$f" | grep -c "op timing over")
  echo "=== $f: $n tables"
  [ "$n" -gt 0 ] || continue
  echo "--- first table"; sed 's/\x1b\[[0-9;]*m//g' "$f" | awk '/op timing over/{c++} c==1' | head -32
  echo "--- last table";  sed 's/\x1b\[[0-9;]*m//g' "$f" | awk -v n="$n" '/op timing over/{c++} c==n' | head -32
done
