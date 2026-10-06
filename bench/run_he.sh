#!/usr/bin/env bash
# Reasoning budget and effort on Mirai (docs/ROADMAP.md item 3; DECISIONS.md 02:50): HumanEval 164 on the inner port,
# scored in the WASI sandbox, one arm per server setting. Restarts the product launcher between arms (1 min) and
# restores the defaults at the end. Output: bench/humaneval/<arm>/ and receipts/mirai-port/humaneval.log
#   bench/run_he.sh [H0 H3 H1 H2]     (default order: baseline first, cheap arm second, restarts last)
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/humaneval.log"
restart() { env "$@" bash "$ROOT/bench/product_smoke.sh" --start-only >/dev/null 2>&1; grep -E "^listen" "$ROOT/logs/product.launcher.log" | cut -c1-110; }
he() { # ARM_DIR HARNESS_ARM MAX_TOKENS [ENV...]
  local dir=$1 arm=$2 mt=$3; shift 3
  echo "--- $dir ($arm, max_tokens $mt, ${*:-no env}) $(date '+%H:%M')" | tee -a "$LOG"
  env "$@" PYTHONUTF8=1 python "$ROOT/bench/humaneval_wasi.py" --arm "$arm" --max-tokens "$mt" --out "$ROOT/bench/humaneval/$dir" 2>&1 | tail -3 | tee -a "$LOG"
}
echo "=== HumanEval grid $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
ARMS=("$@"); [ ${#ARMS[@]} -eq 0 ] && ARMS=(H0 H3 H1 H2)
for A in "${ARMS[@]}"; do case $A in
  H0) echo "server: product defaults (medium, budget 20480)" | tee -a "$LOG"; restart | tee -a "$LOG"; he H0-medium-20k medium 24576 ;;
  H3) echo "server: product defaults; thinking off per request" | tee -a "$LOG"; he H3-off off 4096 ;;
  H1) echo "server: MIRAI_THINK_BUDGET=8192" | tee -a "$LOG"; restart MIRAI_THINK_BUDGET=8192 | tee -a "$LOG"; he H1-medium-8k medium 12288 ;;
  H2) echo "server: MIRAI_EFFORT_ALLOWED=low,medium (effort low sent per request)" | tee -a "$LOG"; restart MIRAI_EFFORT_ALLOWED=low,medium | tee -a "$LOG"; he H2-low-20k medium 24576 HE_KW_EFFORT=low ;;
esac; done
echo "server: restoring product defaults" | tee -a "$LOG"; restart | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
