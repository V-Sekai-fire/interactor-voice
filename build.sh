#!/usr/bin/env bash
# Build voice.elf into project/.
#
#   RISCV64_SYSROOT=<dir with toolchain.cmake and sysroot/> ./build.sh
#
# Needs cmake, ninja, a clang++ with a riscv64 target, and the riscv64 glibc sysroot that
# interactor-dress-on's build.sh uses. No V extension: the Linux addon traps on vector code.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSROOT="${RISCV64_SYSROOT:?set RISCV64_SYSROOT to the riscv64 sysroot (toolchain.cmake inside)}"
BUILD="${BUILD_DIR:-$HERE/build}"

if [ ! -f "$SYSROOT/toolchain.cmake" ]; then
	echo "error: no toolchain.cmake under RISCV64_SYSROOT=$SYSROOT" >&2
	exit 1
fi
has_riscv() { "$1" --print-targets 2>/dev/null | grep -qi riscv64; }
if ! { command -v clang++ >/dev/null 2>&1 && has_riscv clang++; }; then
	echo "error: no clang++ with a riscv64 target on PATH" >&2
	exit 1
fi

if [ ! -f "$BUILD/build.ninja" ]; then
	cmake -S "$HERE" -B "$BUILD" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$SYSROOT/toolchain.cmake" \
		-DCMAKE_BUILD_TYPE=Release \
		-DSANDBOX_RISCV_EXT_V=OFF
fi
cmake --build "$BUILD" -- -j "${BUILD_JOBS:-8}"
ls -la "$HERE/project/voice.elf"
sha256sum "$HERE/project/voice.elf"
