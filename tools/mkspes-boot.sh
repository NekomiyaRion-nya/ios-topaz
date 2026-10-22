#!/bin/bash
# spes: ADT (3 GB at 0x80000000) + payload + shim boot.img v3, in two flavours:
#   shim/out/spes-debug.img  kernel console drawn on screen (slow, for the first boots)
#   shim/out/spes-boot.img   console off once iOS draws (normal use)
#   shim/out/spes-notouch.img debug, touch driver off (isolates touch bring-up hangs)
#   shim/out/spes-touchstep.img debug, touch steps logged 1.5 s apart, log flushed every 1 s
set -euo pipefail
cd "$(dirname "$0")/.."
K=${K:-xnu/out/kernel.development.sweet}   # K=... to use another kernel (e.g. a local xnu-linux build)
COMMON='debug=0xc serial=3 cpus=CPUS keepsyms=1 -noprogress rd=ufsroot0 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30 sweetusb=2 sweetchg=0'
# sweettouchdiag=1 is not in COMMON: when the probe finds no IC it panics on purpose, the panic is
# only drawn on screen and the unflushed log looked like a SoC freeze (2026-10-22).
# sweetchg=0: topaz charger limits (topaz-0148) stay off until checked on spes.
# test images reset into fastboot after AUTOREBOOT s (tools/spes-cycle.sh pulls the log)
AUTO="sweetautoreboot=${AUTOREBOOT:-360} sweethwwdt=${HWWDT:-20}"
# AMP=1: a TOPAZ_4K=1 (4 KiB pages) kernel on all eight cores: ADT --amp, cpus=8, images named spes-*-amp.img
COMMON=${COMMON/cpus=CPUS/cpus=${AMP:+8}}; COMMON=${COMMON/cpus= /cpus=4 }
SFX=${AMP:+-amp}
mkdir -p shim/out
python3 tools/mkadt.py shim/out/spes$SFX.adt --mem 0x80000000:0xc0000000 ${AMP:+--amp}
# GPUFILES=DIR (userland/gpu/build-linux.sh: DIR/topaz/lib/*): the gpu images carry these files and the
# kernel installs them into the iOS root before launchd (spes-0965)
GPUFILES=${GPUFILES:-}
build() {  # name cmdline
	local files=()
	[ -n "$GPUFILES" ] && [ "${1#gpu}" != "$1" ] && files=(--files "$GPUFILES")
	python3 tools/mkpayload.py "$K" shim/out/spes$SFX.adt shim/out/payload-$1$SFX.bin --cmdline "$2" "${files[@]}"
	bash shim/build.sh "$(pwd)/shim/out/payload-$1$SFX.bin" >/dev/null
	cp shim/out/shim-boot.img shim/out/spes-$1$SFX.img
}
build debug "$COMMON $AUTO"
build notouch "$COMMON $AUTO sweettouch=0 sweetsample=SpringBoard,lsd,backboardd"
build touchstep "$COMMON $AUTO ufslogsecs=1 sweettouchstep=1500 sweettouchdelay=20"
build usb "$COMMON $AUTO sweettouch=0 sweetusb=2"
build battery "$COMMON $AUTO sweettouch=0 sweetbattery=1"
# touch with the FT3418 power sequence of 0162 (L9A on); step log to see each stage
build touch "$COMMON $AUTO ufslogsecs=1 sweettouchdelay=20 sweettouchmode=1"
build touchnol9a "$COMMON $AUTO ufslogsecs=1 sweettouchstep=300 sweettouchdelay=20 sweettouchl9a=0"
# GPU: Adreno 610 via TopazAdreno/RedwoodGPU (kernel) + Mesa freedreno behind EAGL in backboardd (GPUFILES)
GPUARGS="gpu=1 gpu_midmem=1 gpu_contig=0 topaz_inject=/topaz/lib/libtopaz-inject.dylib,backboardd"
[ -n "$GPUFILES" ] && build gpu "$COMMON $AUTO ufslogsecs=1 sweettouchmode=1 $GPUARGS"
# Wi-Fi: TopazModem boots the modem from modem_a through TrustZone (spes tables, 0966), wifid through Apple80211 glue
build wifi "$COMMON $AUTO sweettouchmode=1 modem=1 wifi=1"
# PROBE: extra boot-args for one investigation run (tools/spes-cycle.sh)
build probe "$COMMON $AUTO sweettouch=0 ${PROBE:-}"
build boot "$COMMON sweetfb_noconsole=1 sweettouchmode=1 modem=1 wifi=1 sweethwwdt=20"   # boot_a/boot_b: everyday iOS with touch; tests ask it for fastboot over USB (UDP 5141)
ls -l shim/out/spes-*.img
