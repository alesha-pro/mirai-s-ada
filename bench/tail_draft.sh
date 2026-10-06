#!/usr/bin/env bash
# The tail draft past the VRAM line vs the recurrent-state rollback snapshots it costs (150 MiB per unit of rollback
# depth on this model). For tail = 2, 3, 4 (draft 2 below the line in all arms): VRAM at load, the recurrent buffer
# line, decode at 60k and 120k (both past the ~31k line). Output: receipts/mirai-port/tail_draft.log
cd "$(dirname "$0")" && . ./lib.sh
LOG="$ROOT/receipts/mirai-port/tail_draft.log"
BASEF="-b 2048 -ub 512 --kv-vram-cells 31488 --spec-type draft-mtp --spec-draft-n-max 2 -ctkd q8_0 -ctvd q8_0 --spec-draft-window 16384 --backend-sampling -lv 5"
echo "=== tail draft $(date '+%F %H:%M') engine $(cd "$ROOT/engine" && git rev-parse --short HEAD); idle $(nvidia-smi --query-gpu=memory.used --format=csv,noheader)" | tee -a "$LOG"
for T in 2 3 4; do
  start_server T$T 262144 "$BASEF --spec-draft-n-max-tail $T" | tail -1 | tee -a "$LOG"
  echo "T$T $(sed 's/\x1b\[[0-9;]*m//g' "$ROOT/logs/T$T.log" | grep -E "n_rs_seq|RS buffer size" | cut -c14-120 | tr '\n' ';')" | tee -a "$LOG"
  for d in 60000 120000; do echo "T$T depth $d: $(tps_at $d)" | tee -a "$LOG"; done
  echo "T$T vram_after=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader | head -1)" | tee -a "$LOG"
done
stop_server | tee -a "$LOG"
echo "=== done $(date '+%H:%M')" | tee -a "$LOG"
