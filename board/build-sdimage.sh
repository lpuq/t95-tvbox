#!/usr/bin/env bash
# Assemble a bootable SD image (no root needed).
#   0 .. 8 KiB      MBR
#   8 KiB           TOC0-signed U-Boot (boot ROM looks here)
#   16 MiB ..       p1 ext4 LABEL=$ROOT_LABEL (grown to full device on first boot)
# The same rootfs makes both images; only the root label differs, so an SD
# card and the eMMC can both be present without mounting each other's root:
#   board/build-sdimage.sh                                -> out/t95-sd.img   (t95-root)
#   ROOT_LABEL=t95-emmc IMG_NAME=emmc board/build-sdimage.sh -> out/t95-emmc.img (t95-emmc)
set -euo pipefail

W=$(cd "$(dirname "$0")/.." && pwd)
OUT=$W/out
ROOT_LABEL=${ROOT_LABEL:-t95-root}
IMG=$OUT/t95-${IMG_NAME:-sd}.img
ROOT_MB=${ROOT_MB:-3072}
UBOOT=$OUT/u-boot-sunxi-with-spl.bin
TAR=$OUT/rootfs.tar

for f in "$UBOOT" "$TAR"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
head -c 8 "$UBOOT" | grep -q 'TOC0.GLH' || { echo "U-Boot is not TOC0"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Safety net: overlay files must be root-owned (sync-in keeps host uid 1000).
OVERLAY_PATHS=$(cd "$W/board/rootfs-overlay" && find . | tr '\n' ' ')

# rootfs.tar -> ext4 image; fakeroot keeps tar's owners/devnodes for mkfs -d
fakeroot sh -e -c "
	mkdir '$TMP/root'
	tar -C '$TMP/root' -xpf '$TAR'
	cd '$TMP/root' && for p in $OVERLAY_PATHS; do chown -h 0:0 \"\$p\"; done; cd /
	# point fstab, u-boot-menu and the generated extlinux.conf at this label
	sed -i 's/LABEL=t95-root/LABEL=$ROOT_LABEL/' '$TMP/root/etc/fstab' \
		'$TMP/root/etc/u-boot-menu/conf.d/t95.conf' '$TMP/root/boot/extlinux/extlinux.conf'
	grep -q 'LABEL=$ROOT_LABEL' '$TMP/root/boot/extlinux/extlinux.conf'
	mkfs.ext4 -q -F -L $ROOT_LABEL -O ^metadata_csum_seed -E root_owner=0:0 \
		-d '$TMP/root' '$TMP/root.ext4' ${ROOT_MB}M
"

rm -f "$IMG"
truncate -s $((16 + ROOT_MB))M "$IMG"
echo 'start=32768, type=83, bootable' | sfdisk -q --label dos "$IMG"
dd if="$TMP/root.ext4" of="$IMG" bs=1M seek=16 conv=notrunc,fsync status=none
dd if="$UBOOT" of="$IMG" bs=1K seek=8 conv=notrunc,fsync status=none

sfdisk -l "$IMG"
echo "OK: $IMG  ->  write with: sudo dd if=$IMG of=/dev/sdX bs=4M conv=fsync status=progress"
