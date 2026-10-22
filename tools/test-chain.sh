#!/bin/bash
# Git Bash: wait for the phone in fastboot, then run test cycles back to back (staying in fastboot between
# them; the USB live log replaces the OrangeFox pull where it caught the run), then boot the everyday iOS.
#   tools/test-chain.sh JOB...      JOB = NAME:IMAGE (shim/out) | NAME:- (pull the UFS log of the last run)
HACK=/c/Users/matsu/Documents/hackinOS
PT=/c/Users/matsu/Documents/rom/platform-tools
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "waiting for the phone in fastboot"
end=$((SECONDS + 3600))
until "$PT/fastboot.exe" devices 2>/dev/null | grep -q 14e0ddb2; do
	sleep 3
	[ $SECONDS -ge $end ] && { log "gave up waiting"; exit 2; }
done
"$PT/fastboot.exe" set_active a 2>&1 | tail -1
for job in "$@"; do
	name=${job%%:*} img=${job#*:}
	[ "$img" = - ] || img="$HACK/ios-spes/shim/out/$img"
	log "=== $name"
	if [ "$img" = - ]; then
		PULL=1 PARK=0 bash "$HACK/tools/spes-cycle.sh" - "$name" 600
	else
		PARK=0 bash "$HACK/tools/spes-cycle.sh" "$img" "$name" 420
	fi
	rc=$?
	log "$name finished rc=$rc"
	[ $rc -eq 0 ] || { log "stopping (rc=$rc)"; break; }
done
"$PT/fastboot.exe" reboot 2>&1 | tail -1
log "done (everyday iOS)"
