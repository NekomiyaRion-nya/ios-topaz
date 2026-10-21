#!/bin/bash
# Print the C string a CFString constant in the shared cache points to: cfstr.sh VADDR...
grep -q hfsplus /proc/filesystems || insmod /opt/src/wsl-kernel/fs/hfsplus/hfsplus.ko
mountpoint -q /mnt/iosroot || { mkdir -p /mnt/iosroot; mount -t hfsplus -o loop,ro /root/iosbuild/ios16-root.img /mnt/iosroot; }
DSC=/mnt/iosroot/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
for a in "$@"; do
	echo "== $a"; ipsw dyld dump "$DSC" "$a" --size 32 --no-color 2>/dev/null | head -3
done
