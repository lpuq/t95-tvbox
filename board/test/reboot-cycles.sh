#!/usr/bin/env bash
# Warm-reboot the T95 N times over SSH and check it comes back healthy each time.
# Usage: board/test/reboot-cycles.sh CYCLES USER@HOST   (key login + passwordless sudo needed)
# Stops at the first failed cycle. Log: logs/reboot-cycles.log
N=${1:-20}; H=${2:?usage: reboot-cycles.sh CYCLES USER@HOST}
LOG=$(cd "$(dirname "$0")/../.." && pwd)/logs/reboot-cycles.log
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=4 -o ServerAliveInterval=5 "$H")
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

# checks run on the box; prints one summary line, exit 1 if anything is off
read -r -d '' CHECK <<'EOF'
export LANG=C LC_ALL=C
bad=
mem=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo); [ "$mem" -gt 3800 ] || bad="$bad mem"
emmc=$(cat /sys/block/mmcblk1/size 2>/dev/null); [ "$emmc" = 61071360 ] || bad="$bad emmc-size"
sudo dd if=/dev/mmcblk1 of=/dev/null bs=1M count=64 iflag=direct status=none || bad="$bad emmc-read"
nic=$(ls -d /sys/class/net/enx* | head -1); [ "$(cat $nic/carrier)" = 1 ] || bad="$bad carrier"
drv=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null); [ "$drv" = cpufreq-dt ] || bad="$bad cpufreq"
[ -e /sys/class/thermal/thermal_zone2/cdev0 ] || bad="$bad cooling"
state=$(systemctl is-system-running --wait 2>/dev/null); [ "$state" = running ] || bad="$bad state=$state"
errs=$(journalctl -b -p err -o cat --no-pager | grep -vcE "pam_env|Could not set hostname|regulatory.db")
[ "$errs" = 0 ] || bad="$bad errs=$errs"
kerr=$(journalctl -b -k --no-pager | grep -ciE "mmc.*(error|timeout|failed)|lockup|oops|call trace")
[ "$kerr" = 0 ] || bad="$bad kernel=$kerr"
bt=$(systemd-analyze time 2>/dev/null | grep -o '= [0-9.]*s' | head -1)
echo "boot=$(cut -c1-8 /proc/sys/kernel/random/boot_id) mem=${mem}M emmc=ok? cpufreq=$drv state=$state errs=$errs boottime${bt#=}${bad:+ FAIL:$bad}" | sed "s/emmc=ok? /emmc=${emmc:-none} /"
[ -z "$bad" ]
EOF

log "=== reboot cycles: $N ==="
prev=$("${SSH[@]}" cat /proc/sys/kernel/random/boot_id) || { log "cannot reach box"; exit 1; }
for i in $(seq 1 "$N"); do
	"${SSH[@]}" 'sudo systemctl reboot' >/dev/null 2>&1
	t0=$(date +%s)
	# wait for it to go away (max 90 s), then come back (max 240 s)
	while "${SSH[@]}" true 2>/dev/null; do [ $(($(date +%s)-t0)) -gt 90 ] && { log "cycle $i: never went down"; exit 1; }; sleep 2; done
	until "${SSH[@]}" true 2>/dev/null; do [ $(($(date +%s)-t0)) -gt 240 ] && { log "cycle $i: NOT BACK after 240 s"; exit 1; }; sleep 3; done
	up=$(($(date +%s)-t0))
	id=$("${SSH[@]}" cat /proc/sys/kernel/random/boot_id)
	[ "$id" != "$prev" ] || { log "cycle $i: boot_id unchanged - did not reboot"; exit 1; }
	prev=$id
	if out=$("${SSH[@]}" "$CHECK" 2>&1); then log "cycle $i ok (ssh back in ${up}s) $out"
	else log "cycle $i FAILED (ssh back in ${up}s) $out"; exit 1; fi
done
log "=== all $N cycles passed ==="
