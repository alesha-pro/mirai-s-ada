#!/usr/bin/env bash
# The VRAM margin on Mirai (docs/ROADMAP.md item 2). For each margin: start the PRODUCT launcher with
# MIRAI_VRAM_MARGIN set (it sizes more cells into VRAM), then soak for SOAK_MIN minutes alternating decode runs at
# 4k / 16k / 32k depth (bench/quick_tps.py, 3 prompts x 400 tokens each) while logging decode tok/s and nvidia-smi.
# Demotion shows as decode falling under DEMOTE_TPS (half the healthy ~70) or prefill under 200 tok/s. Ends by
# restarting the product with its default margin. Output: receipts/mirai-port/margin_soak.log
#   bench/margin_soak.sh [margins...]   (default: 800 800 600)   SOAK_MIN=10
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/margin_soak.log"
SOAK_MIN=${SOAK_MIN:-10}; DEMOTE_TPS=${DEMOTE_TPS:-40}
INNER="http://127.0.0.1:18080"
echo "=== margin soak $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD); soak ${SOAK_MIN} min per margin" | tee -a "$LOG"
MARGINS=("$@"); [ ${#MARGINS[@]} -eq 0 ] && MARGINS=(800 800 600)
for M in "${MARGINS[@]}"; do
  MIRAI_VRAM_MARGIN=$M bash "$ROOT/bench/product_smoke.sh" --start-only >/dev/null 2>&1
  echo "--- margin $M: $(grep '^kv' "$ROOT/logs/product.launcher.log" | cut -c1-90); at load $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
  end=$(( $(date +%s) + SOAK_MIN * 60 )); worst=999; demoted=0; i=0
  while [ "$(date +%s)" -lt "$end" ]; do
    for d in 4000 16000 32000; do
      line=$(PYTHONUTF8=1 python "$ROOT/bench/quick_tps.py" --base "$INNER" --key-file "$ROOT/artifacts/api_key.txt" --depth $d 2>&1 | tail -1)
      tps=$(echo "$line" | grep -o -E "[0-9]+\.[0-9]+ tok/s" | head -1 | cut -d' ' -f1)
      used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 | tr -d ' ')
      i=$((i+1)); echo "margin $M run $i depth $d: $line; vram $used MiB" | tee -a "$LOG"
      if [ -n "$tps" ]; then
        awk -v t="$tps" -v w="$worst" 'BEGIN{exit !(t<w)}' && worst=$tps
        awk -v t="$tps" -v th="$DEMOTE_TPS" 'BEGIN{exit !(t<th)}' && demoted=1
      fi
      [ "$(date +%s)" -lt "$end" ] || break
    done
  done
  echo "--- margin $M verdict: worst decode $worst tok/s, demotion=$demoted, vram end $(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
done
# never pipe the product launcher's output: the hidden launcher inherits the pipe and the reader never gets EOF
bash "$ROOT/bench/product_smoke.sh" --start-only > "$ROOT/logs/product_restore.log" 2>&1
grep -E "inner health|layer health" "$ROOT/logs/product_restore.log" | tee -a "$LOG"
echo "=== done $(date '+%H:%M'); product restored with the default margin" | tee -a "$LOG"
