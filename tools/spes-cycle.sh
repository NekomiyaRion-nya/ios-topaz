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
log() { echo "[$(date +%H:%M:%S)] $*"; }
in_fastboot() { "$FB" devices 2>/dev/null | grep -q "$SERIAL"; }
in_recovery() { "$ADB" devices 2>/dev/null | grep -q -E "$SERIAL\s+recovery"; }
wait_for() {  # cond seconds
	local t=0
	until $1; do sleep 3; t=$((t + 3)); [ $t -ge "$2" ] && return 1; done
}

wait_for in_fastboot 60 || { log "phone not in fastboot"; exit 2; }
log "booting $IMG"
"$FB" boot "$(winpath "$IMG")" 2>&1 | tail -1
sleep 20   # leave fastboot before polling for its return
log "waiting up to ${MAX}s for the automatic reset into fastboot"
if ! wait_for in_fastboot "$MAX"; then
	log "no reset within ${MAX}s: hung? hold Power + Vol-down, then rerun with the pull step"
	exit 3
fi
log "back in fastboot; booting OrangeFox"
"$FB" boot "$RECOVERY" 2>&1 | tail -1
wait_for in_recovery 120 || { log "OrangeFox did not show up on adb"; exit 4; }
mkdir -p "$HACK/logs"
dev=/dev/block/sda16   # userdata on spes (by-name link resolves here)
bytes=$(MSYS_NO_PATHCONV=1 "$ADB" -s $SERIAL shell blockdev --getsize64 $dev | tr -d '\r')
skip=$((bytes / 4096 - 1025))
MSYS_NO_PATHCONV=1 "$ADB" -s $SERIAL exec-out "dd if=$dev bs=4096 skip=$skip count=1025 2>/dev/null" > "$HACK/logs/$NAME.bin"
python "$HACK/ios-spes/tools/sweet-log.py" "$HACK/logs/$NAME.bin" "$HACK/logs/$NAME.txt" | tail -1
log "log: logs/$NAME.txt ($(wc -l < "$HACK/logs/$NAME.txt") lines)"
"$ADB" -s $SERIAL reboot bootloader
wait_for in_fastboot 60 && log "phone back in fastboot, ready for the next cycle"
