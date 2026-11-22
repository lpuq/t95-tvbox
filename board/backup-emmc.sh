#!/usr/bin/env bash
# Resumable full-eMMC backup over adb, in 1 GiB chunks.
# Each chunk is hashed on the box AND on the host; a chunk is kept only when
# both hashes match. Re-run after any disconnect: finished chunks are skipped.
# Output: backup/emmc/chunk-NNN.zst + chunk-NNN.sha256
set -uo pipefail

W=$(cd "$(dirname "$0")/.." && pwd)
D=$W/backup/emmc
# with several adb devices attached, pick one: SERIAL=<adb serial> board/backup-emmc.sh
A="adb${SERIAL:+ -s $SERIAL}"
CHUNK_MB=1024
mkdir -p "$D"

$A wait-for-device
$A root >/dev/null 2>&1; sleep 3; $A wait-for-device
[ "$($A shell id -u | tr -d '\r')" = 0 ] || { echo "adb root failed"; exit 1; }

BYTES=$($A shell 'cat /sys/block/mmcblk0/size' | tr -d '\r'); BYTES=$((BYTES * 512))
N=$(( (BYTES + CHUNK_MB*1024*1024 - 1) / (CHUNK_MB*1024*1024) ))
echo "eMMC: $BYTES bytes, $N chunks of ${CHUNK_MB} MiB"

for ((i = 0; i < N; i++)); do
	c=$(printf '%03d' "$i")
	[ -f "$D/chunk-$c.sha256" ] && continue
	# Single read on the box: dd -> tee -> (fifo -> sha256sum on box) + stdout to host.
	# (/data is live, so reading twice could legitimately differ.)
	host=$($A exec-out "F=/data/local/tmp/bk.fifo; rm -f \$F /data/local/tmp/bk.sha; mkfifo \$F; \
		(sha256sum < \$F > /data/local/tmp/bk.sha) & \
		dd if=/dev/block/mmcblk0 bs=1M skip=$((i*CHUNK_MB)) count=$CHUNK_MB 2>/dev/null | tee \$F; wait" \
		| tee >(zstd -T0 -3 -q -f -o "$D/chunk-$c.zst.part") | sha256sum | awk '{print $1}')
	sleep 1
	dev=$($A shell 'cat /data/local/tmp/bk.sha; rm -f /data/local/tmp/bk.fifo /data/local/tmp/bk.sha' | awk '{print $1}')
	if [ -n "$dev" ] && [ "$dev" = "$host" ]; then
		mv "$D/chunk-$c.zst.part" "$D/chunk-$c.zst"
		echo "$host" > "$D/chunk-$c.sha256"
		echo "chunk $c/$((N-1)) OK $host"
	else
		echo "chunk $c MISMATCH dev=$dev host=$host - re-run to retry"; rm -f "$D/chunk-$c.zst.part"; exit 1
	fi
done
echo "$BYTES" > "$D/total-bytes"
echo "ALL $N CHUNKS VERIFIED. Restore: cat chunk-*.zst | zstd -d | dd of=<emmc>"
