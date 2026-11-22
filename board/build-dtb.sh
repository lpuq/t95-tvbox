#!/usr/bin/env bash
# Build the T95 DTB against a given kernel tree's dtsi/bindings.
# Usage: build-dtb.sh [kernel-src-dir]   (default: src/linux-6.12, = Debian trixie)
set -euo pipefail

W=$(cd "$(dirname "$0")/.." && pwd)
K=${1:-$W/src/linux-6.12}
DTS=$W/board/sun50i-h616-t95.dts
OUT=$W/out/sun50i-h616-t95.dtb

mkdir -p "$W/out"
cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
	-I "$K/arch/arm64/boot/dts/allwinner" \
	-I "$K/arch/arm64/boot/dts" \
	-I "$K/include" \
	-I "$K/scripts/dtc/include-prefixes" \
	"$DTS" | dtc -I dts -O dtb -@ -o "$OUT" -
echo "OK: $OUT"
