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
| Touch | FocalTech @0x38, QUP0 SE2, IRQ 80, reset 86, AVDD GPIO36 (EAST) | FocalTech `focaltech,fts` @0x38, QUP0 SE2, IRQ 80, reset 86, **AVDD GPIO98 (SOUTH)**, vcc_i2c L9A | patch 0140; raw scale unknown → `sweettouchmode=1` if touches land at 0.8× |
| Battery | SM5602 0x71 + bq2589x 0x6a on SE1 | **MAX77729 0x66 + SC8551 0x65** on SE1 | not ported: boot with `sweetbattery=0` (static 100 %) |
| Modem / Wi-Fi | `modem_a`, topaz firmware hash table | A-only (`modem`), different firmware | not ported: leave `modem`/`wifi` unset (off) |
| DDR | 4 GB map hard-coded (`--highmem`) | unknown until the first boot | default ADT range `0xb0000000+0x4d000000`; the shim prints ABL's `/memory` ranges (`DDR base/size`) — then `mkadt.py --mem BASE:SIZE` |

## First boots

1. **Diagnostic** (no payload, touches nothing): `shim/build.sh` → `fastboot boot shim/out/shim-boot.img`.
   Red screen: `MMFR0`, `MEMNODES`, `DDR base/size` lines, gold hand-off, then `LOADER no SWEETXNU payload`.
   Photograph it; hold Power + Vol-down to get back to fastboot.
2. **iOS**: flash the root to `userdata` and boot with
   `... rd=ufsroot0 ufsrw=1 rootrw=1 cpus=1 sweetbattery=0 sweettouchdiag=1` (add `cpus=4`, drop diag once stable).

Before anything destructive: back up `persist`, `modemst1`, `modemst2`, `fsg`, `fsc` (see RECOVERY.md).
