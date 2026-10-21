#!/bin/bash
# Run a list of unattended test cycles as soon as the phone shows up in fastboot.
# Usage: tools/spes-queue.sh NAME:IMAGE [NAME:IMAGE...]   (images relative to ios-spes/shim/out)
# While a cycle runs, Windows' USB device list is sampled every 10 s into
# logs/NAME.usb.txt (to see whether the iOS-side USB gadget enumerates).
set -uo pipefail
HACK=/c/Users/matsu/Documents/hackinOS
PT=/c/Users/matsu/Documents/rom/platform-tools
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "waiting for the phone in fastboot (up to 12 h)"
end=$((SECONDS + 43200))
until "$PT/fastboot.exe" devices 2>/dev/null | grep -q 14e0ddb2; do
	sleep 10
	[ $SECONDS -ge $end ] && { log "gave up waiting"; exit 2; }
done
# FLASHBOOT=1: first put the current spes-boot.img (normal iOS, USB Ethernet, fastboot on request)
# into boot_a/boot_b, so parking between cycles boots a reachable iOS.
if [ "${FLASHBOOT:-0}" = 1 ]; then
	for slot in a b; do
		"$PT/fastboot.exe" flash boot_$slot "$(cygpath -w "$HACK/ios-spes/shim/out/spes-boot.img")" 2>&1 | tail -1
	done
fi
for job in "$@"; do
	name=${job%%:*} img=${job#*:}
	log "=== $name ($img)"
	( while :; do
		date +%H:%M:%S
		powershell.exe -NoProfile -Command "Get-PnpDevice -PresentOnly | Where-Object { \$_.InstanceId -match 'VID_1209|VID_18D1|VID_2717' } | ForEach-Object { \$_.Status + ' ' + \$_.FriendlyName + ' ' + \$_.InstanceId }" 2>/dev/null
		sleep 10
	done ) > "$HACK/logs/$name.usb.txt" 2>&1 &
	usbpid=$!
	bash "$HACK/tools/spes-cycle.sh" "$HACK/ios-spes/shim/out/$img" "$name" 600
	rc=$?
	kill $usbpid 2>/dev/null
	log "$name finished rc=$rc"
	if [ $rc -eq 5 ]; then
		log "USB link to fastboot is broken: stopping (replug / restart fastboot)"
		exit 5
	fi
	if [ $rc -eq 3 ]; then
		log "phone did not come back: stopping the queue (needs Power + Vol-down)"
		exit 3
	fi
done
log "queue done"
