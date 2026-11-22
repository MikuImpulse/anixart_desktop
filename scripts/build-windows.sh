#!/usr/bin/env bash
set -euo pipefail

if (( $# > 2 )) || [[ -z "${1:-${MSYSTEM_PREFIX:-}}" ]]; then
    printf 'Usage: %s <path-to-ucrt64> [output-dir]\n' "$0" >&2
    exit 2
fi

project=$(cd "$(dirname "$0")/.." && pwd)
sdk=$(cd "${1:-$MSYSTEM_PREFIX}" && pwd)
build_path=${ANIXART_BUILD_DIR:-$project/build/windows}
build=$(mkdir -p "$build_path" && cd "$build_path" && pwd)
output=${2:-$project/dist}

if [[ $(uname -s) == Linux ]]; then
    run=(wine)
    to_windows() { winepath -w "$1" | tr '\\' '/'; }
    export WINEPATH="$(winepath -w "$sdk/bin")"
    packager=(python3)
else
    run=()
    to_windows() { cygpath -am "$1"; }
    packager=("$sdk/bin/python.exe")
fi

sdk_windows=$(to_windows "$sdk")
"${run[@]}" "$sdk/bin/cmake.exe" -S "$(to_windows "$project")" -B "$(to_windows "$build")" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$sdk_windows" \
    -DCMAKE_MAKE_PROGRAM="$sdk_windows/bin/ninja.exe" -DCMAKE_CXX_COMPILER="$sdk_windows/bin/g++.exe" \
    -DCMAKE_RC_COMPILER="$sdk_windows/bin/windres.exe" -DPKG_CONFIG_EXECUTABLE="$sdk_windows/bin/pkgconf.exe"
"${run[@]}" "$sdk/bin/cmake.exe" --build "$(to_windows "$build")" --parallel "${ANIXART_BUILD_JOBS:-$(nproc)}"
"${packager[@]}" "$project/scripts/package-windows.py" "$build/Anixart.exe" "$sdk" "$output/Anixart-Windows-x64.zip"
