#!/bin/bash
# spes: the GPU's user space on Linux (WSL), for the boot image's --files tree:
#   /topaz/lib/libOSMesa.8.dylib     Mesa (userland/mesa/mk-mesa-linux.sh)
#   /topaz/lib/libtopaz-gl.dylib     eagl.c + gl_osmesa.c: OpenGL ES behind EAGLContext (CoreAnimation)
#   /topaz/lib/libtopaz-inject.dylib topaz_inject.c: loaded into backboardd (boot-arg
#                                    topaz_inject=/topaz/lib/libtopaz-inject.dylib,backboardd), opens libtopaz-gl
# mkeagl.py and eagl_slots.txt are HackiOS' (MIT, see CREDITS.md).
#   W=/root/gpu-ul bash userland/gpu/build-linux.sh      -> $W/files/topaz/lib/*
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
W=${W:-/root/gpu-ul}
SDK=${SDK:-/root/ios-sdk/sdks/iPhoneOS16.5.sdk}
M=$W/mesa/out
O=$W/obj
F=$W/files/topaz/lib
mkdir -p "$O" "$F"
[ -f "$M/libOSMesa.8.dylib" ] || { echo "build Mesa first (userland/mesa/mk-mesa-linux.sh)" >&2; exit 1; }
CC=(clang-17 -target arm64-apple-ios16.0 -isysroot "$SDK" -O2 -Wall -Wno-unused-function
	-fuse-ld=lld -mlinker-version=711 -Wl,-adhoc_codesign -Wl,-x)
python3 "$HERE/mkeagl.py" "$HERE/eagl_slots.txt" "$M/gl.xml" "$M/exported-gl.txt" "$HERE/eagl.c" > "$O/eagl_gen.h"
"${CC[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-gl.dylib -I"$O" -I"$HERE" \
	-framework CoreFoundation -framework IOKit -framework IOSurface -lobjc "$M/libOSMesa.8.dylib" \
	-o "$F/libtopaz-gl.dylib" "$HERE/eagl.c" "$HERE/gl_osmesa.c"
"${CC[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-inject.dylib -I"$HERE" \
	-framework CoreFoundation -framework IOKit -lobjc \
	-o "$F/libtopaz-inject.dylib" "$HERE/topaz_inject.c"
cp "$M/libOSMesa.8.dylib" "$F/"
chmod 0755 "$F"/*.dylib
ls -l "$F"
