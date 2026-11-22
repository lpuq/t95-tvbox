#!/usr/bin/env bash
# PC-side network watcher for the T95: logs only state changes (up/down),
# plus an hourly "still up" line. Usage: pingwatch.sh IP [logfile]
IP=${1:?usage: pingwatch.sh IP [logfile]}; LOG=${2:-$(dirname "$0")/../../logs/ping.log}
state=; last=0
while :; do
	if ping -c1 -W2 "$IP" >/dev/null 2>&1; then s=up; else s=DOWN; fi
	now=$(date +%s)
	if [ "$s" != "$state" ] || [ $((now - last)) -ge 3600 ]; then
		echo "$(date '+%F %T %Z') $IP $s" >> "$LOG"; state=$s; last=$now
	fi
	sleep 10
done
