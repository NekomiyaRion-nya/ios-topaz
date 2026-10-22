#!/bin/bash
# One unattended test cycle on the Redmi Note 11 (Git Bash on Windows):
#   fastboot boot IMAGE -> (kernel sweetautoreboot resets into fastboot)
#   -> fastboot boot OrangeFox -> pull + decode the iOS log -> back to fastboot.
# Usage: tools/spes-cycle.sh IMAGE NAME [MAX_SECONDS]
# The phone must start in fastboot. Exit 3 = phone never came back (hang: needs a
# manual Power + Vol-down).
set -uo pipefail
IMG=$1 NAME=$2 MAX=${3:-600}
HACK=/c/Users/matsu/Documents/hackinOS
PT=/c/Users/matsu/Documents/rom/platform-tools
FB=$PT/fastboot.exe ADB=$PT/adb.exe SERIAL=14e0ddb2
RECOVERY='C:\Users\matsu\Documents\rom\platform-tools\recovery.img'
winpath() { cygpath -w "$1"; }
fb_retry() {  # fastboot command with up to 3 tries (Xiaomi fastboot drops the link now and then)
	local i
	for i in 1 2 3; do
		"$FB" "$@" 2>&1 | tail -1 | tee /dev/stderr | grep -q -v -E "FAILED|error" && return 0
		sleep 5
	done
	return 1
}
log() { echo "[$(date +%H:%M:%S)] $*"; }
in_fastboot() { "$FB" devices 2>/dev/null | grep -q "$SERIAL"; }
in_recovery() { "$ADB" devices 2>/dev/null | grep -q -E "$SERIAL\s+recovery"; }
wait_for() {  # cond seconds (wall clock)
	local end=$((SECONDS + $2))
	until $1; do sleep 3; [ $SECONDS -ge $end ] && return 1; done
	return 0
}

request_fastboot() {  # iOS parked with USB Ethernet up (kernel 0158/0159): ask it to reboot into fastboot
	MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -u root -- bash /mnt/c/Users/matsu/Documents/hackinOS/tools/phone-fastboot.sh >/dev/null 2>&1
}
if ! wait_for in_fastboot 15; then
	log "not in fastboot: asking iOS over USB Ethernet"
	request_fastboot
	wait_for in_fastboot 180 || { log "phone not in fastboot"; exit 2; }
fi
if [ "$IMG" != - ]; then   # IMAGE "-": only pull the log of the last run
L0=$(wc -l < "$HACK/logs/live.txt")
log "booting $IMG"
fb_retry boot "$(winpath "$IMG")" || { log "fastboot cannot reach the phone (USB link)"; exit 5; }
sleep 20   # leave fastboot before polling for its return
log "waiting up to ${MAX}s for the automatic reset into fastboot"
if ! wait_for in_fastboot "$MAX"; then
	log "no reset within ${MAX}s: hung? hold Power + Vol-down, then rerun with the pull step"
	exit 3
fi
fi
# PULL=auto (default): the USB live log already holds the run when it grew by more than 50 lines; then
# skip OrangeFox (a minute) and keep that part as logs/NAME.live.txt. PULL=1 always pulls the UFS log.
if [ "${PULL:-auto}" != 1 ] && [ -n "${L0:-}" ] && [ $(( $(wc -l < "$HACK/logs/live.txt") - L0 )) -gt 50 ]; then
	tail -n +"$L0" "$HACK/logs/live.txt" > "$HACK/logs/$NAME.live.txt"
	log "log: logs/$NAME.live.txt ($(wc -l < "$HACK/logs/$NAME.live.txt") lines, USB live log; OrangeFox skipped)"
	if [ "${PARK:-1}" = 1 ]; then
		fb_retry reboot >/dev/null && log "parked in iOS (boot partition)"
	fi
	exit 0
fi
log "back in fastboot; booting OrangeFox"
fb_retry boot "$RECOVERY" || { log "fastboot cannot reach the phone (USB link)"; exit 5; }
wait_for in_recovery 120 || { log "OrangeFox did not show up on adb"; exit 4; }
mkdir -p "$HACK/logs"
dev=/dev/block/sda16   # userdata on spes (by-name link resolves here)
bytes=$(MSYS_NO_PATHCONV=1 "$ADB" -s $SERIAL shell blockdev --getsize64 $dev | tr -d '\r')
skip=$((bytes / 4096 - 1025))
MSYS_NO_PATHCONV=1 "$ADB" -s $SERIAL exec-out "dd if=$dev bs=4096 skip=$skip count=1025 2>/dev/null" > "$HACK/logs/$NAME.bin"
python "$HACK/ios-spes/tools/sweet-log.py" "$HACK/logs/$NAME.bin" "$HACK/logs/$NAME.txt" | tail -1
log "log: logs/$NAME.txt ($(wc -l < "$HACK/logs/$NAME.txt") lines)"
"$ADB" -s $SERIAL reboot bootloader
wait_for in_fastboot 60 && log "phone back in fastboot"
# Park in iOS (boot partition image, USB Ethernet up) instead of idling in ABL fastboot,
# whose USB drops out after a few idle minutes. The next cycle asks for fastboot over UDP.
if [ "${PARK:-1}" = 1 ]; then
	fb_retry reboot >/dev/null && log "parked in iOS (boot partition)"
fi
