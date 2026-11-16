#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${CLAP_WRAPPER_SOURCE:?Set CLAP_WRAPPER_SOURCE to the free-audio/clap-wrapper source directory}"
: "${CLAP_SDK_ROOT:?Set CLAP_SDK_ROOT to the free-audio/clap source directory}"
: "${AUDIOUNIT_SDK_ROOT:?Set AUDIOUNIT_SDK_ROOT to the Apple AudioUnitSDK source directory}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "AUv2 wrapper builds require macOS" >&2
    exit 1
fi

cd "$ROOT"
zig build clap

BUILD_AAX=OFF
if [[ "${DANZIG_BUILD_AAX:-OFF}" == "ON" ]]; then
    : "${AAX_SDK_ROOT:?Set AAX_SDK_ROOT to the licensed Avid SDK when DANZIG_BUILD_AAX=ON}"
    BUILD_AAX=ON
fi

cmake -S "$ROOT/wrappers" -B "$ROOT/zig-out/format-wrappers" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCLAP_WRAPPER_SOURCE="$CLAP_WRAPPER_SOURCE" \
    -DCLAP_SDK_ROOT="$CLAP_SDK_ROOT" \
    -DAUDIOUNIT_SDK_ROOT="$AUDIOUNIT_SDK_ROOT" \
    -DAAX_SDK_ROOT="${AAX_SDK_ROOT:-}" \
    -DDANZIG_CLAP_BUNDLE="$ROOT/zig-out/DanzigGain.clap" \
    -DDANZIG_BUILD_AAX="$BUILD_AAX"
cmake --build "$ROOT/zig-out/format-wrappers" --config Release --parallel
