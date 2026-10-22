# ios-spes: ios-topaz on the Redmi Note 11 (spes)

Branch `spes` of [MakrSas/ios-topaz](https://github.com/MakrSas/ios-topaz). The Redmi Note 11
(`spes`/`spesn`, Snapdragon 680) is the same SoC as topaz (SM6225 "khaje", msm-id 0x206), so the
kernel, shim and root image are topaz's with the board differences below.

## spes vs topaz (from the spes vendor_boot DTB + dtbo, Infinity-X 3.2 2025-09-25)

| | topaz | spes | Status |
| --- | --- | --- | --- |
| Boot image | v4 | **v3** (boot + vendor_boot v3) | `shim/build.sh` defaults to v3 (`BOOT_HEADER_VERSION=4` for topaz); payload stays appended to the Image |
| GIC / UFS / PS_HOLD / IMEM | `0xf200000` / `0x4804000` / `0x440b000` / `0xc125000` | same | — |
| Splash framebuffer | `0x5c000000` + `0xf00000` | same | — |
| Panel | 1080×2400 DSI video, DSC | 1080×2400 OLED DSI video, DSC (K7 `38 0c 0a`/`0b`, NT36672E variants) | as topaz; brightness/DCS (0104–0106) unverified |
| Touch | FT5452 (id 54:52) @0x38, QUP0 SE2, IRQ 80, reset 86, AVDD GPIO36 (EAST), raw 1.25× | **FT3418 (id 34:18, Xiaomi `ft3418_i2c`)** @0x38, QUP0 SE2, IRQ 80, reset 86, **AVDD GPIO98 (SOUTH)**, vcc_i2c L9A 1.8 V, raw = panel pixels | 0140 (pins), 0141 (step log), 0147 (FT3418 id, unscaled). Bring-up still hangs the SoC (open) |
| Battery | SM5602 0x71 + bq2589x 0x6a on SE1 | **MAX77729** (PMIC 0x66, fuel gauge 0x36, charger 0x69) + SC8551 0x65 on SE1 | **This phone answers on topaz's SM5602 0x71 + bq2589x 0x6a** (2026-10-22: 100 %, 4424 mV, full 4849 mAh); the MAX77729 node is another board variant. `pollSpes` (0146) tries MAX77729 first, then topaz. Battery on by default |
| Modem / Wi-Fi | `modem_a`, topaz firmware hash table | A-only (`modem`), different firmware | not ported: leave `modem`/`wifi` unset (off) |
| DDR | 4 GB map hard-coded (`--highmem`, `0x1_40000000`+4G) | **4 GB: `0x40000000+0x3dd00000`, `0x80000000+1G`, `0xc0000000+2G`** (ABL `/memory`, 2026-10-21). Nothing at `0x1_40000000` | **`mkadt.py --mem 0x80000000:0xc0000000`** (contiguous 3 GB, below every fixed carve-out ≤ `0x64000000`). Never `--highmem` on spes |

## First boots

1. **Diagnostic** (no payload, touches nothing): `shim/build.sh` → `fastboot boot shim/out/shim-boot.img`.
   Red screen: `MMFR0`, `MEMNODES`, `DDR base/size` lines, gold hand-off, then `LOADER no SWEETXNU payload`.
   Photograph it; hold Power + Vol-down to get back to fastboot.
2. **iOS**: flash the root to `userdata` and boot with
   `... rd=ufsroot0 ufsrw=1 rootrw=1 cpus=1 sweetbattery=0 sweettouchdiag=1` (add `cpus=4`, drop diag once stable).

Before anything destructive: back up `persist`, `modemst1`, `modemst2`, `fsg`, `fsc` (see RECOVERY.md).

## Observed on the phone

- 2026-10-21, diagnostic shim (`fastboot boot`, boot v3): ABL accepts v3; Silver MIDR `0x51AF8014` (tg16=0),
  Gold hand-off OK (MIDR `0x411FD090`, MPIDR `0x80000100`, tg16=1), GICv3 SGI/vtimer OK on Gold,
  GICR for `0x101`–`0x103` prepared, Gold cpufreq 0x960 = 2400 (as topaz), initrd `0x4548e000`, DDR as above.
- 2026-10-21, first iOS boots (root image flashed to `userdata`, debug image): kernel, UFS root, display (60 Hz),
  launchd, SpringBoard, backboardd all start; Apple logo stays.
  - **Touch bring-up freezes the whole SoC** about 45 s in (log stops; `sweettouch=0` runs for 10+ min, keys reach HID).
    Under investigation with `spes-touchstep.img` (0141 `sweettouchstep`). Suspects: L9A (touch vcc_i2c) off on spes, AVDD GPIO98.
  - **Apple logo forever = MobileGestalt waiting for Wi-Fi**: SpringBoard waits in `_LSContextInitCommon`, lsd in
    `GenerateBuiltInAppInstallSessionID` -> libMobileGestalt MGIOKitSupport: no `/chosen/mac-address-wifi0`, the ADT has a
    `wlan` node, so it waits forever for an `IONetworkController` (Wi-Fi is off on spes). Fix: mkadt adds synthetic
    `mac-address-wifi0`/`mac-address-bluetooth0`.

## Unattended test loop

`tools/spes-cycle.sh IMAGE NAME` (Git Bash on the PC, phone in fastboot): boots IMAGE, the kernel resets into fastboot after
`sweetautoreboot` seconds (0142, flushed log first), then OrangeFox is booted and the log is pulled to `logs/NAME.txt`.
Symbolicate samples with `tools/a2s.sh SLIDE ADDR...`, disassemble with `tools/disass.sh VADDR` (inside WSL, as root).

## Kernel patches (spes)

| Patch | What |
| --- | --- |
| 0140 | Touch AVDD on GPIO98 (SOUTH tile), `sweettouchmode` |
| 0141 | `sweettouchstep=MS`: log each touch bring-up step and wait |
| 0142 | `sweetautoreboot=SECS`: flush the log, reset into fastboot |
| 0143 | PMIC writes over SPMI; reboot reason BOOTLOADER (PON SOFT_RB_SPARE 0x88F) + warm PS_HOLD reset (needed: the IMEM reason alone is ignored and Android boots and **wipes userdata**) |
| 0144 | `sweetautoreboot` uses 0143 |
| 0145 | `sweethwwdt=SECS`: APSS watchdog (0xf017000) petted every second; a hang bites into fastboot |
| 0146 | MAX77729 battery readout |
| 0147 | FT3418 touch IC |
| 0148-0150 | USB (DWC3 0x4e00000, GCC 0x1400000) for the CDC-ECM live log |
| 0151-0157 | Touch hang bisection: DFS level dump, `sweettouchtest` bits, per-register transfer trace |
| 0960 | L9A through the RPM: polled GLINK (RPM message RAM) + SMD RPM client `sweet_rpm.c` (ldoa9 1.8 V, active + sleep set). New spes patches go after topaz 09xx (0960+): patches apply in name order and must match the tree they were made on |
| 0162 | FT3418 power as the Xiaomi `ft3418_i2c` driver: reset low, AVDD GPIO98, **vcc_i2c = PM6125 L9A enabled over SPMI** (SID0 0x4800 EN_CTL, only if VSET is 1.7-1.95 V; `sweettouchl9a=0` skips), chip id retried ~1 s |
| 0158/0159 | `SWEET-FASTBOOT` UDP datagram (port 5141, USB Ethernet) reboots into fastboot |
| 0160/0161 | (removed at the topaz merge, superseded by upstream TopazAdreno) `SweetGPU.cpp`: Adreno 610 G1 test (`sweetgpu=1`): power, zap via TZ PAS 13 into gpu_region 0x56615000, SMMU CB0 pass-through, SQE + CP_ME_INIT, CP_MEM_WRITE 0xC0FFEE00 readback. Firmware from the spes vendor partition in `/arm-io/sweet-gpu` |

boot_a/boot_b hold `spes-boot.img` (the iOS shim) since 2026-10-22, so a normal boot never reaches Android again.
- 2026-10-22: USB works (0148-0150): `ue0` 192.168.7.2 up, Windows enumerates "Sweet iOS (USB Ethernet)" (1209:0001).
  Host side: usbipd-win (AutoBind policy for 1209:0001) + `tools/usb-attach.sh` (Git Bash) + `tools/livelog.sh` (WSL root)
  -> `logs/live.txt`. Touch hangs at the first I2C transfer ("step probe"); 0151 dumps the SE2 DFS table and picks an XO level.
- 2026-10-22 touch: the SoC freezes after the first SE2 I2C transfer completes (FT3418 at 0x38 NACKs). The transfer
  itself is harmless (2 s alive with SE2 untouched) and all SE2 registers read fine afterwards; GIC SPI 361 (SE2)
  reads as Group 0 / RAZ from the non-secure side. Next: trace the NACK/abort paths (0157, image `spes-tt17.img`).
- ABL fastboot drops off USB after a few idle minutes: the test loop now parks the phone in iOS and asks for fastboot
  over UDP (`tools/phone-fastboot.sh`).
- 2026-10-22 GPU **G1 passed** (`spes-gpu.img`, log `logs/gpu3.txt`): GX/CX GDSC up, zap shader via TZ PAS 13
  (init_image / mem_setup / auth_and_reset all 0), SMMU CB0 pass-through, SQE + CP_ME_INIT, and
  `CP_MEM_WRITE` came back as `0xC0FFEE00`: the Adreno 610 executes our command stream. No SMMU fault
  (CB0 FSR 0x400 is only FORMAT=AArch64), iOS kept running until `sweetautoreboot`. (The earlier `gpu2` log
  was the parked boot image, not the GPU image.)
- 2026-10-22 touch, paused: across tt17/17c/29/49/51/81/209 the log always stops right before a read of SE2
  `M_IRQ_STATUS` (0x610), after 0-6 good transfers; other SE2 reads (0x68/0x20/0x28/0x40/0x48/0x800) are fine.
  `sweethwwdt` bites ~20 s later (back in fastboot ~100 s after boot), so EL3 is alive and the APSS is stuck.
  Possible: a synchronous/SError abort -> XNU panic whose text is never flushed (no panic hook writes the
  UFS log). Next: a panic hook that flushes the log (or sends it over the USB live log) before hanging.
  Upstream topaz touch (same SoC, same driver, FT5452) works; no touch changes upstream since the fork.

## 2026-10-22: upstream topaz merged; the touch "freeze" was a deliberate panic

- Merged upstream ios-topaz `fe7625f` (HackiOS-derived GPU via Mesa, AMP/4K pages behind `TOPAZ_4K=1`, audio,
  charger limits, Wi-Fi glue). GPU/audio/modem/Wi-Fi are off unless `gpu=1`/`adsp=1`/`modem=1`/`wifi=1`;
  spes images pass `sweetchg=0`. The GPU userland (eagl + Mesa freedreno) is not built yet (needs a Mac or CI).
- Touch: every test image had `sweettouchdiag=1`, which **panics on purpose** when the probe finds no supported IC
  (topaz diag). The probe always failed (FT3418 NACKs at 0x38), the panic text only went to the screen, the last
  second of the log was never flushed, and `sweethwwdt` brought the phone back: that was the "SoC freeze".
  GENI SE2 itself works (clean NACKs). Real problem: the IC does not answer -> its vcc_i2c (L9A, used otherwise
  only by BT IO and the codec) is off after ABL. 0162 turns it on. Images: `spes-touch.img` / `spes-touchnol9a.img`.

## 2026-10-22 23:25: TOUCH WORKS on spes

- Root cause: **GPIO98 (touch AVDD enable) is an eGPIO** on khaje (CFG bit 11 EGPIO_PRESENT). TLMM must set
  EGPIO_ENABLE (bit 12) to own the pad (pinctrl-msm.c msm_pinmux_set_mux); without it the output never left the
  SoC, the IC had no power, nothing ACKed on the bus (0961 bit-banged scan) and IRQ never moved. 0962 claims eGPIO
  pins in `touch_gpio`. L9A (vcc_i2c) is also voted on via the RPM (0960, `sweet_rpm.c`, GLINK in RPM msg RAM).
- The IC answers **54:52** (FT5452 id, fw 0x17, vendor 0x48) at 0x38, not 34:18, but reports in panel pixels
  (1080x2400), so spes needs `sweettouchmode=1` (topaz's 1.25x scaling put the bottom edge at y=1919).
- Phone reached the home screen by touch. Local WSL kernel builds (hackinOS/xnu-linux, ~25 s incremental) are used
  from here on (`K=xnu/out-local/... tools/mkspes-boot.sh`); they differ from CI in codegen (clang-17) and
  kalloc_type signatures.
- ABL refused `fastboot boot` with "Load Error" once current-slot had become b (slot b unbootable after the parked
  iOS never marks boot success): `fastboot set_active a` fixed it.

## 2026-10-23 night: AMP and GPU prepared (not yet run on the phone)

- **Local builds**: kernel `hackinOS/xnu-linux/build.sh` (~25 s incremental; `TOPAZ_4K=1` as a make arg, `FRESH=1`
  when switching page size). GPU user space on Linux too: `userland/mesa/mk-mesa-linux.sh` (Mesa 25.0.7
  freedreno+softpipe, clang-17 + ld64.lld + theos iPhoneOS16.5.sdk, ad-hoc signed) and `userland/gpu/build-linux.sh`
  (libtopaz-gl = eagl.c + gl_osmesa.c, libtopaz-inject = topaz_inject.c; mkeagl.py/eagl_slots.txt from HackiOS).
- **AMP** (`AMP=1 K=<TOPAZ_4K kernel> tools/mkspes-boot.sh` -> `spes-*-amp.img`): `mkadt.py --amp` (gold P 0x100-0x103
  first, silver E 0x0-0x3), cpus=8, shim prepares the silver GICRs and powers the silver boot CPU off (PSCI CPU_OFF)
  once gold runs so xnu can CPU_ON it.
- **GPU** (`GPUFILES=/root/gpu-ul/files ... tools/mkspes-boot.sh` -> `spes-gpu.img`): 0964 loads zap/SQE from the
  ADT (spes' own, the embedded topaz zap mdt differs) and refuses topaz's 0x90000000 pool (kernel RAM on spes);
  boot-args `gpu=1 gpu_midmem=1 gpu_fbpool=0 topaz_inject=/topaz/lib/libtopaz-inject.dylib,backboardd`.
  0965 + `mkpayload.py --files`: the boot image carries /topaz/lib/* and the kernel installs them into the iOS root
  before launchd (only when changed) - no userdata flash needed.
- Night of 10-22/23: after flashing the touch-enabled everyday image to boot_a/b (23:55, CI kernel 0962) the phone
  did not show up on USB again (no fastboot, no USB Ethernet); needs a look in the morning.
- **Wi-Fi** (0966, `spes-wifi.img`, boot-args `modem=1 wifi=1`): TopazModem's firmware tables regenerated from this
  phone's modem_a (`tools/modem-fwtable.py backup-spes-20261021/modem_a.img`: 611 files under /image, each one
  extent; modem_a == modem_b) and the 16 MB modem pool moved to 0x70000000 (topaz' 0xE0000000 is kernel RAM on
  spes; first-bank fixed carve-outs end at 0x63900000, bank ends 0x7DD00000). Untested.
- `tools/overnight-tests.sh`: waits for the phone, runs gpu1 / amp1 / wifi1 (logs/NAME.txt + NAME.live.txt),
  stays in fastboot between them, then reboots into the boot-partition iOS.
