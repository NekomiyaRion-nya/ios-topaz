#!/bin/bash
# spes: Mesa 25.0.7 (freedreno + softpipe, OSMesa with the OpenGL ES profile) for the iOS 16 userland,
# built on Linux (WSL) instead of a Mac: the same meson options as mk-mesa-mac.sh, with clang-17,
# LLVM's Mach-O linker (ld64.lld reads the SDK's .tbd stubs) and theos' iPhoneOS16.5.sdk.
#   W=/root/gpu-ul  SDK=/root/ios-sdk/sdks/iPhoneOS16.5.sdk  bash userland/mesa/mk-mesa-linux.sh
# Output: $W/mesa/out/libOSMesa.8.dylib (install name /topaz/lib/libOSMesa.8.dylib), exported-gl.txt, gl.xml
set -euo pipefail
VERSION=25.0.7
SHA256=592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6
ROOT=$(cd "$(dirname "$0")/.." && pwd)            # ios-spes/userland
W=${W:-/root/gpu-ul}
SDK=${SDK:-/root/ios-sdk/sdks/iPhoneOS16.5.sdk}
HOSTBIN=${HOSTBIN:-/root/xnu-linux/host/bin}       # install_name_tool (cctools)
B=$W/mesa
mkdir -p "$B/out"
cd "$B"
PATCHES=$(cat "$ROOT"/mesa/*.patch | sha256sum | cut -d' ' -f1)
if [ ! -d mesa-$VERSION ] || [ "$(cat mesa-$VERSION/.redwood-patches 2>/dev/null)" != "$PATCHES" ]; then
	[ -f mesa-$VERSION.tar.xz ] || curl -sL --fail -o mesa-$VERSION.tar.xz https://archive.mesa3d.org/mesa-$VERSION.tar.xz
	echo "$SHA256  mesa-$VERSION.tar.xz" | sha256sum -c --quiet
	rm -rf mesa-$VERSION build-*
	tar xJf mesa-$VERSION.tar.xz
	for p in "$ROOT"/mesa/*.patch; do patch -s --no-backup-if-mismatch -d mesa-$VERSION -p1 < "$p"; done
	echo "$PATCHES" > mesa-$VERSION/.redwood-patches
fi
rm -rf mesa-$VERSION/src/redwood-drm
cp -r "$ROOT/mesa/redwood-drm" mesa-$VERSION/src/redwood-drm
if [ ! -x venv/bin/meson ]; then
	python3 -m venv venv
	venv/bin/pip -q install meson mako pyyaml packaging
fi
export PATH=$B/venv/bin:$PATH
T="'-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK'"
L="'-fuse-ld=lld', '-mlinker-version=711', '-Wl,-adhoc_codesign'"
cat > cross.ini <<INI
[binaries]
c = ['clang-17', $T]
cpp = ['clang++-17', $T, '-fuse-cxa-atexit']
objc = ['clang-17', $T]
ar = 'llvm-ar-17'
ranlib = 'llvm-ranlib-17'
strip = 'llvm-strip-17'
pkg-config = 'false'

[built-in options]
c_link_args = [$L]
cpp_link_args = [$L]
objc_link_args = [$L]

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
INI
DRIVERS=${DRIVERS:-softpipe,freedreno}
BUILD=build-${DRIVERS//,/-}
[ -f $BUILD/build.ninja ] || meson setup $BUILD mesa-$VERSION --cross-file cross.ini --wrap-mode=nofallback \
	--prefix=/topaz --libdir=lib --buildtype=release -Db_ndebug=true \
	-Dplatforms= -Dgallium-drivers="$DRIVERS" -Dfreedreno-kmds=msm -Dvulkan-drivers= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
	-Dosmesa=true -Dllvm=disabled -Dshared-glapi=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
	-Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled -Dvalgrind=disabled \
	-Dlibunwind=disabled -Dglvnd=disabled -Dvideo-codecs= -Dtools= -Dgallium-vdpau=disabled -Dgallium-va=disabled \
	-Dgallium-xa=disabled -Dlmsensors=disabled -Dbuild-tests=false > meson-setup.log
ninja -C $BUILD > ninja.log
# Link once more with the final install name and the local symbols stripped, instead of
# install_name_tool/strip afterwards: those would leave the ad-hoc signature (-adhoc_codesign) invalid.
LINK=$(ninja -C $BUILD -t commands src/gallium/targets/osmesa/libOSMesa.8.dylib | tail -1)
LINK=${LINK//@rpath\/libOSMesa.8.dylib//topaz/lib/libOSMesa.8.dylib}
LINK=${LINK/-o src\/gallium\/targets\/osmesa\/libOSMesa.8.dylib/-o $B/out/libOSMesa.8.dylib -Wl,-x -Wl,-S}
(cd $BUILD && eval "$LINK")
llvm-nm-17 -gU out/libOSMesa.8.dylib | awk '$3 ~ /^_gl/ { print substr($3, 2) }' > out/exported-gl.txt
cp mesa-$VERSION/src/mapi/glapi/registry/gl.xml out/gl.xml
ls -l out
