#!/bin/sh
# Builds vendor/libgit2 as a static library for one Apple SDK and architecture:
#   scripts/libgit2/build.sh <macosx|iphoneos|iphonesimulator> <arch> <out-dir>
# The result is <out-dir>/libgit2.a. Only the system zlib, CommonCrypto and
# SecureTransport are used, so every SDK links the same way (-lz, -liconv on the
# Mac, Security and CoreFoundation) and nothing but libgit2 itself is vendored.
# SSH, NTLM and GSSAPI need further third-party libraries and stay off.
set -eu
SDK=$1
ARCH=$2
OUT=$3
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SOURCE=$ROOT/vendor/libgit2
test -f "$SOURCE/CMakeLists.txt" || {
	echo "vendor/libgit2 is missing; run: git submodule update --init vendor/libgit2" >&2
	exit 1
}
SYSROOT=$(xcrun --sdk "$SDK" --show-sdk-path)
case $SDK in
	macosx) SYSTEM="-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DUSE_ICONV=ON" ;;
	iphoneos|iphonesimulator) SYSTEM="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=26.5 -DUSE_ICONV=OFF" ;;
	*) echo "unknown SDK: $SDK" >&2; exit 1 ;;
esac
mkdir -p "$OUT/cmake"
# shellcheck disable=SC2086
cmake -S "$SOURCE" -B "$OUT/cmake" -DCMAKE_BUILD_TYPE=Release $SYSTEM \
	-DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
	-DCMAKE_C_COMPILER="$(xcrun --sdk "$SDK" --find clang)" \
	-DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF -DBUILD_CLI=OFF -DBUILD_EXAMPLES=OFF \
	-DUSE_SSH=OFF -DUSE_HTTPS=SecureTransport -DUSE_SHA1=CollisionDetection -DUSE_SHA256=CommonCrypto \
	-DUSE_NTLMCLIENT=OFF -DUSE_GSSAPI=OFF -DUSE_BUNDLED_ZLIB=OFF -DUSE_HTTP_PARSER=builtin \
	-DREGEX_BACKEND=builtin -DUSE_THREADS=ON >"$OUT/cmake.log"
cmake --build "$OUT/cmake" --target libgit2package --parallel "$(sysctl -n hw.ncpu)" >>"$OUT/cmake.log"
cp "$OUT/cmake/libgit2.a" "$OUT/libgit2.a"
