#!/bin/bash
# Symbolicate shared-cache addresses from a SWEET "SMP" sample: a2s.sh SLIDE ADDR...
set -euo pipefail
grep -q hfsplus /proc/filesystems || insmod /opt/src/wsl-kernel/fs/hfsplus/hfsplus.ko
mountpoint -q /mnt/iosroot || { mkdir -p /mnt/iosroot; mount -t hfsplus -o loop,ro /root/iosbuild/ios16-root.img /mnt/iosroot; }
DSC=$(ls /mnt/iosroot/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64 2>/dev/null || find /mnt/iosroot/System/Cryptexes /mnt/iosroot/private/preboot -name dyld_shared_cache_arm64 2>/dev/null | head -1)
slide=$1; shift
for a in "$@"; do
	printf '%s ' "$a"; ipsw dyld a2s --cache /root/dsc.a2s "$DSC" $(printf '0x%x' $((a - slide))) 2>/dev/null | tail -1
done
