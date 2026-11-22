#!/usr/bin/env bash
# Build TF-A BL31 + mainline U-Boot (TOC0-signed) for the T95 H616 box.
# Output: out/u-boot-sunxi-with-spl.bin  (dd to SD/eMMC at 8 KiB)
set -euo pipefail

W=$(cd "$(dirname "$0")/.." && pwd)
SRC=$W/src
OUT=$W/out
KEYS=$W/keys
JOBS=$(nproc)
export CROSS_COMPILE=aarch64-linux-gnu-

mkdir -p "$OUT" "$KEYS"

# TOC0 root key. The ROTPK fuse is empty (sunxi_rotpk: 0), so the boot ROM
# accepts any key; keep this one stable so every build is signed the same way.
if [ ! -f "$KEYS/root_key.pem" ]; then
	openssl genrsa -out "$KEYS/root_key.pem" 2048
	chmod 600 "$KEYS/root_key.pem"
fi

# --- TF-A ---
for pt in "$W"/board/patches/tf-a/*.patch; do
	[ -e "$pt" ] || continue
	git -C "$SRC/tf-a" apply --reverse --check "$pt" 2>/dev/null && continue  # already applied
	git -C "$SRC/tf-a" apply "$pt"; echo "applied $(basename "$pt")"
done
make -C "$SRC/tf-a" -j"$JOBS" PLAT=sun50i_h616 DEBUG=0 bl31
BL31=$SRC/tf-a/build/sun50i_h616/release/bl31.bin

# --- U-Boot ---
for pt in "$W"/board/patches/u-boot/*.patch; do
	git -C "$SRC/u-boot" apply --reverse --check "$pt" 2>/dev/null && continue  # already applied
	git -C "$SRC/u-boot" apply "$pt"; echo "applied $(basename "$pt")"
done
cp "$W/board/sun50i-h616-t95.dts" "$SRC/u-boot/dts/upstream/src/arm64/allwinner/"
cp "$W/board/t95_h616_defconfig" "$SRC/u-boot/configs/"
make -C "$SRC/u-boot" -j"$JOBS" O="$W/build/u-boot" t95_h616_defconfig
make -C "$SRC/u-boot" -j"$JOBS" O="$W/build/u-boot" BL31="$BL31" SCP=/dev/null KEYDIR="$KEYS"

cp "$W/build/u-boot/u-boot-sunxi-with-spl.bin" "$OUT/"
head -c 8 "$OUT/u-boot-sunxi-with-spl.bin" | grep -q 'TOC0.GLH' \
	&& echo "OK: TOC0 image -> $OUT/u-boot-sunxi-with-spl.bin" \
	|| { echo "ERROR: output is not a TOC0 image"; exit 1; }
