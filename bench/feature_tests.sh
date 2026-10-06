#!/usr/bin/env bash
# Mirai S on our engine, within the card's VRAM budget (DECISIONS.md 2026-10-04 21:35):
#   A) MTP draft at the product batch (-b 2048 -ub 512), 64k all-VRAM window
#   B) tiered KV, 262k window, KV_CELLS cells in VRAM (default 32768), no MTP
#   C) both
# Each: restart hidden, health + VRAM, greedy identity against the stock-fork dump, decode/prefill by depth.
# Output: receipts/mirai-port/feature_tests.log.  Usage: bench/feature_tests.sh [A] [B] [C]   KV_CELLS=<n>
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/feature_tests.log"
BATCH="-b 2048 -ub 512"
MTP="--spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --spec-draft-n-max-tail 4 --backend-sampling"
CELLS="${KV_CELLS:-32768}"
measure() { local label=$1; shift
  echo "$label greedy-identical (thinking off): $(greedy_identity stock-greedy-nothink.json)" | tee -a "$LOG"
  for d in "$@"; do echo "$label depth $d: $(tps_at $d)" | tee -a "$LOG"; done
  echo "$label vram_after=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
}
run() { case $1 in
  A) echo "=== A) MTP draft, 64k q8 all-VRAM, $BATCH  $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD)" | tee -a "$LOG"
     start_server A 65536 "$BATCH $MTP" | tee -a "$LOG" && measure A 0 16000 32000 60000 ;;
  B) echo "=== B) tiered KV 262k, $CELLS cells in VRAM, no MTP, $BATCH  $(date '+%F %H:%M')" | tee -a "$LOG"
     start_server B 262144 "$BATCH --kv-vram-cells $CELLS" | tee -a "$LOG" && measure B 0 32000 60000 120000 ;;
  C) echo "=== C) tiered KV 262k, $CELLS cells, MTP, $BATCH  $(date '+%F %H:%M')" | tee -a "$LOG"
     start_server C 262144 "$BATCH $MTP --kv-vram-cells $CELLS" | tee -a "$LOG" && measure C 0 32000 60000 120000 180000 ;;
esac; }
ARMS=("$@"); [ ${#ARMS[@]} -eq 0 ] && ARMS=(A B C)
for t in "${ARMS[@]}"; do run $t; done
stop_server | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
