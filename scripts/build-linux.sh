#!/usr/bin/env bash
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
    printf 'Usage: %s <deb|rpm|arch> [output-dir]\n' "$0" >&2
    exit 2
fi

project=$(cd "$(dirname "$0")/.." && pwd)
format=$1
case "$format" in
    deb) generator=DEB ;;
    rpm) generator=RPM ;;
    arch) ;;
    *) printf 'Unknown Linux package format: %s\n' "$format" >&2; exit 2 ;;
esac

build=$(realpath -m "${ANIXART_BUILD_DIR:-$project/build/linux-$format}")
output=$(realpath -m "${2:-$project/dist}")
mkdir -p "$output"

cmake -S "$project" -B "$build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build" --parallel "${ANIXART_BUILD_JOBS:-$(nproc)}"

if [[ "$format" == arch ]]; then
    ANIXART_BUILD_DIR="$build" PKGDEST="$output" BUILDDIR="$build" makepkg --dir "$project/packaging/arch" --force
else
    cpack --config "$build/CPackConfig.cmake" -G "$generator" -B "$output"
fi
