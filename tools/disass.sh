#!/bin/bash
# Disassemble shared-cache code: disass.sh UNSLID_VADDR [COUNT]
grep -q hfsplus /proc/filesystems || insmod /opt/src/wsl-kernel/fs/hfsplus/hfsplus.ko
mountpoint -q /mnt/iosroot || { mkdir -p /mnt/iosroot; mount -t hfsplus -o loop,ro /root/iosbuild/ios16-root.img /mnt/iosroot; }
DSC=/mnt/iosroot/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
ipsw dyld disass "$DSC" --vaddr "$1" --count "${2:-80}" --force --no-color --cache /root/dsc.a2s 2>&1
