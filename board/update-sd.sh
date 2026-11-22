#!/usr/bin/env bash
# Update an already-written T95 SD card in place (run with sudo):
#   - replace the TOC0 U-Boot at 8 KiB with out/u-boot-sunxi-with-spl.bin
#   - install out/sun50i-h616-t95.dtb
#   - sync board/rootfs-overlay onto the card (root-owned)
#   - sync kernel parameters from the overlay's u-boot-menu conf.d into the
#     card (conf.d file + generated extlinux.conf)
# Usage: sudo board/update-sd.sh /dev/sdX
set -euo pipefail

DEV=${1:?usage: sudo $0 /dev/sdX}
W=$(cd "$(dirname "$0")/.." && pwd)
UBOOT=$W/out/u-boot-sunxi-with-spl.bin
CONF=$W/board/rootfs-overlay/etc/u-boot-menu/conf.d/t95.conf

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -b "$DEV" ] || { echo "$DEV is not a block device"; exit 1; }
[ "$(cat /sys/block/$(basename "$DEV")/removable)" = 1 ] || { echo "$DEV is not removable - refusing"; exit 1; }
[ "$(blkid -s LABEL -o value "${DEV}1")" = t95-root ] || { echo "${DEV}1 is not labelled t95-root - refusing"; exit 1; }
[ "$(dd if="$DEV" bs=1 skip=8192 count=8 status=none)" = "TOC0.GLH" ] || { echo "no TOC0 U-Boot at 8 KiB on $DEV - refusing"; exit 1; }
head -c 8 "$UBOOT" | grep -q 'TOC0.GLH' || { echo "$UBOOT is not TOC0"; exit 1; }

umount "${DEV}1" 2>/dev/null || true

# 1. U-Boot (TOC0 must stay below the partition at 16 MiB)
[ "$(stat -c %s "$UBOOT")" -lt $((16*1024*1024 - 8192)) ]
dd if="$UBOOT" of="$DEV" bs=1K seek=8 conv=notrunc,fsync status=none
echo "U-Boot written"

# 2. Device tree + kernel parameters
MNT=$(mktemp -d)
trap 'umount "$MNT" 2>/dev/null; rmdir "$MNT"' EXIT
mount "${DEV}1" "$MNT"
install -m 644 -o root -g root "$W/out/sun50i-h616-t95.dtb" "$MNT/boot/dtbs/t95/sun50i-h616-t95.dtb"
echo "DTB installed"
# rootfs overlay (root-owned on the card); drop files the overlay no longer has
rm -rf "$MNT/etc/systemd/system/serial-getty@ttyS0.service.d"
rsync -rlpt --chown=0:0 "$W/board/rootfs-overlay/" "$MNT/"
echo "overlay synced"
. "$CONF"
sed -i "s|^\(\s*append \)root=.*\$|\1${U_BOOT_ROOT} ${U_BOOT_PARAMETERS}|" "$MNT/boot/extlinux/extlinux.conf"
# keep the rescue entry's trailing 'single'
sed -i "/rescue target/,/append/ s|\(append .*rw\)\$|\1 single|" "$MNT/boot/extlinux/extlinux.conf"
grep -E "append" "$MNT/boot/extlinux/extlinux.conf"
sync
echo "OK: $DEV updated"
