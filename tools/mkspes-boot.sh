#!/bin/bash
# spes: ADT (3 GB at 0x80000000) + payload + shim boot.img v3, in two flavours:
#   shim/out/spes-debug.img  kernel console drawn on screen (slow, for the first boots)
#   shim/out/spes-boot.img   console off once iOS draws (normal use)
#   shim/out/spes-notouch.img debug, touch driver off (isolates touch bring-up hangs)
#   shim/out/spes-touchstep.img debug, touch steps logged 1.5 s apart, log flushed every 1 s
set -euo pipefail
cd "$(dirname "$0")/.."
K=xnu/out/kernel.development.sweet
COMMON='debug=0xc serial=3 cpus=4 keepsyms=1 -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30 sweetbattery=0 sweettouchdiag=1'
# test images reset into fastboot after AUTOREBOOT s (tools/spes-cycle.sh pulls the log)
AUTO="sweetautoreboot=${AUTOREBOOT:-360}"
mkdir -p shim/out
python3 tools/mkadt.py shim/out/spes.adt --mem 0x80000000:0xc0000000
build() {  # name cmdline
	python3 tools/mkpayload.py "$K" shim/out/spes.adt shim/out/payload-$1.bin --cmdline "$2"
	bash shim/build.sh "$(pwd)/shim/out/payload-$1.bin" >/dev/null
	cp shim/out/shim-boot.img shim/out/spes-$1.img
}
build debug "$COMMON $AUTO"
build notouch "$COMMON $AUTO sweettouch=0 sweetsample=SpringBoard,lsd,backboardd"
build touchstep "$COMMON $AUTO ufslogsecs=1 sweettouchstep=1500 sweettouchdelay=20"
build boot "$COMMON sweetfb_noconsole=1"
ls -l shim/out/spes-*.img
