#!/bin/bash
# Git Bash: wait for the phone (fastboot, or iOS with USB Ethernet), then run the GPU and AMP test images,
# pull their logs (logs/gpu1.txt, logs/amp1.txt) and leave the phone parked in the boot-partition iOS.
HACK=/c/Users/matsu/Documents/hackinOS
PT=/c/Users/matsu/Documents/rom/platform-tools
U="/c/Program Files/usbipd-win/usbipd.exe"
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "waiting for the phone (fastboot or USB Ethernet)"
end=$((SECONDS + 43200))
until "$PT/fastboot.exe" devices 2>/dev/null | grep -q 14e0ddb2; do
	if "$U" list 2>/dev/null | grep -qi '1209:0001'; then
		log "iOS USB Ethernet seen: asking for fastboot"
		sleep 20
		MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -u root -- bash /mnt/c/Users/matsu/Documents/hackinOS/tools/phone-fastboot.sh >/dev/null 2>&1
		sleep 60
	fi
	sleep 10
	[ $SECONDS -ge $end ] && { log "gave up"; exit 2; }
done
log "phone in fastboot"
"$PT/fastboot.exe" set_active a 2>&1 | tail -1
for job in gpu1:spes-gpu.img amp1:spes-touch-amp.img wifi1:spes-wifi.img; do
	name=${job%%:*} img=${job#*:}
	L0=$(wc -l < "$HACK/logs/live.txt")
	log "=== $name ($img)"
	bash "$HACK/tools/spes-cycle.sh" "$HACK/ios-spes/shim/out/$img" "$name" 600
	rc=$?
	tail -n +"$L0" "$HACK/logs/live.txt" > "$HACK/logs/$name.live.txt"
	log "$name finished rc=$rc"
	[ $rc -eq 5 ] || [ $rc -eq 3 ] || [ $rc -eq 2 ] && { log "stopping (rc=$rc)"; break; }
	sleep 90   # parked iOS comes up before the next cycle asks it for fastboot
done
log "done"
