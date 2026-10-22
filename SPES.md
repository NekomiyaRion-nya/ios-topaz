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
| 0158/0159 | `SWEET-FASTBOOT` UDP datagram (port 5141, USB Ethernet) reboots into fastboot |
| 0160/0161 | `SweetGPU.cpp`: Adreno 610 G1 test (`sweetgpu=1`): power, zap via TZ PAS 13 into gpu_region 0x56615000, SMMU CB0 pass-through, SQE + CP_ME_INIT, CP_MEM_WRITE 0xC0FFEE00 readback. Firmware from the spes vendor partition in `/arm-io/sweet-gpu` |

boot_a/boot_b hold `spes-boot.img` (the iOS shim) since 2026-10-22, so a normal boot never reaches Android again.
- 2026-10-22: USB works (0148-0150): `ue0` 192.168.7.2 up, Windows enumerates "Sweet iOS (USB Ethernet)" (1209:0001).
  Host side: usbipd-win (AutoBind policy for 1209:0001) + `tools/usb-attach.sh` (Git Bash) + `tools/livelog.sh` (WSL root)
  -> `logs/live.txt`. Touch hangs at the first I2C transfer ("step probe"); 0151 dumps the SE2 DFS table and picks an XO level.
- 2026-10-22 touch: the SoC freezes after the first SE2 I2C transfer completes (FT3418 at 0x38 NACKs). The transfer
  itself is harmless (2 s alive with SE2 untouched) and all SE2 registers read fine afterwards; GIC SPI 361 (SE2)
  reads as Group 0 / RAZ from the non-secure side. Next: trace the NACK/abort paths (0157, image `spes-tt17.img`).
- ABL fastboot drops off USB after a few idle minutes: the test loop now parks the phone in iOS and asks for fastboot
  over UDP (`tools/phone-fastboot.sh`).
