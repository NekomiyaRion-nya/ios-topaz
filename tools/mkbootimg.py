#!/usr/bin/env python3
"""Minimal boot.img packer for header v3/v4 (the subset shim/build.sh uses).

Layout (AOSP bootimg.h): a 4096-byte page holding the header, then the kernel
and the ramdisk, each padded to 4096. v4 adds signature_size (0 here).
"""
import argparse, os, struct


def os_version(ver, patch):
    a, b, c = (int(x) for x in (ver.split('.') + ['0', '0'])[:3])
    y, m = (int(x) for x in patch.split('-')[:2])
    return (a << 25) | (b << 18) | (c << 11) | ((y - 2000) << 4) | m


def pad(b, page=4096):
    return b + b'\0' * (-len(b) % page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--header_version', type=int, default=3)
    ap.add_argument('--kernel', required=True)
    ap.add_argument('--ramdisk', required=True)
    ap.add_argument('--os_version', default='13.0.0')
    ap.add_argument('--os_patch_level', default='2025-01')
    ap.add_argument('--cmdline', default='')
    ap.add_argument('-o', '--output', required=True)
    a = ap.parse_args()
    if a.header_version not in (3, 4):
        raise SystemExit('only boot header v3/v4 are supported')
    kernel = open(a.kernel, 'rb').read()
    ramdisk = open(a.ramdisk, 'rb').read()
    cmd = a.cmdline.encode()
    if len(cmd) >= 1536:
        raise SystemExit('cmdline too long')
    hdr_size = 1580 if a.header_version == 3 else 1584
    hdr = b'ANDROID!' + struct.pack('<4I', len(kernel), len(ramdisk),
                                    os_version(a.os_version, a.os_patch_level), hdr_size)
    hdr += b'\0' * 16 + struct.pack('<I', a.header_version) + cmd.ljust(1536, b'\0')
    if a.header_version == 4:
        hdr += struct.pack('<I', 0)
    assert len(hdr) == hdr_size
    with open(a.output, 'wb') as f:
        f.write(pad(hdr) + pad(kernel) + pad(ramdisk))
    print(f'{a.output}: v{a.header_version} kernel {len(kernel)} ramdisk {len(ramdisk)}')


if __name__ == '__main__':
    main()
