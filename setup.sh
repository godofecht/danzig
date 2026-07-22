#!/usr/bin/env bash
#
# danzig setup: check the toolchain, build, test, and report where the VST3
# bundle lands. Safe to run repeatedly.
#
#   ./setup.sh              build and test
#   ./setup.sh --release    same, with -Doptimize=ReleaseFast
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

SUPPORTED_VERSIONS="0.14.1 0.15.2"
OPTIMIZE_FLAG=""

for arg in "$@"; do
    case "$arg" in
        --release)
            OPTIMIZE_FLAG="-Doptimize=ReleaseFast"
            ;;
        -h|--help)
            sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "setup.sh: unknown argument '$arg'" >&2
            exit 2
            ;;
    esac
done

say()  { printf '\n== %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

# --- 1. Toolchain ----------------------------------------------------------

say "Toolchain"

if ! command -v zig >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: zig is not on PATH.

Install one of the supported versions and try again:

  brew install zig                       # currently ships 0.15.2
  https://ziglang.org/download/          # tarballs for 0.14.1 and 0.15.2

If you keep several toolchains side by side, put the one you want first on
PATH for this shell:

  export PATH="$HOME/zig/0.14.1:$PATH"
EOF
    exit 1
fi

ZIG_BIN="$(command -v zig)"
ZIG_VERSION="$(zig version)"
echo "zig $ZIG_VERSION  ($ZIG_BIN)"

version_supported=0
for v in $SUPPORTED_VERSIONS; do
    [ "$ZIG_VERSION" = "$v" ] && version_supported=1
done

if [ "$version_supported" -eq 0 ]; then
    cat >&2 <<EOF

warning: zig $ZIG_VERSION is untested with danzig.
         CI covers $SUPPORTED_VERSIONS only. The build may still work; if it
         does not, that is the first thing to change.
EOF
fi

UNAME="$(uname -s)"
echo "host: $UNAME $(uname -m)"
if [ "$UNAME" != "Darwin" ]; then
    echo "note: the VST3 bundle and GUI example are macOS-only."
    echo "      The library, unit tests, and CLI examples still build here."
fi

# --- 2. Build --------------------------------------------------------------

say "Build"
zig build ${OPTIMIZE_FLAG:+$OPTIMIZE_FLAG} || fail "zig build failed"
echo "ok"

# --- 3. Test ---------------------------------------------------------------

say "Test"
zig build test ${OPTIMIZE_FLAG:+$OPTIMIZE_FLAG} --summary all || fail "zig build test failed"

# --- 4. VST3 bundle --------------------------------------------------------

if [ "$UNAME" = "Darwin" ]; then
    say "VST3 bundle"
    zig build vst3 ${OPTIMIZE_FLAG:+$OPTIMIZE_FLAG} || fail "zig build vst3 failed"

    BUNDLE="$REPO_ROOT/zig-out/DanzigGain.vst3"
    BINARY="$BUNDLE/Contents/MacOS/DanzigGain"
    [ -f "$BINARY" ] || fail "expected $BINARY to exist after 'zig build vst3'"

    echo "bundle:  $BUNDLE"
    lipo -info "$BINARY"

    cat <<EOF

Install it for your DAW with:

  zig build install-vst3

which copies the bundle to:

  \$HOME/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3

Hosts rescan that folder on launch. See docs/WIKI.md for what a host
currently reports for this bundle.
EOF
fi

# --- 5. Where to go next ---------------------------------------------------

say "Next"
cat <<'EOF'
  zig build run-minimal      run the minimal plugin template offline
  zig build run-standalone   run the WAV gain processor
  zig build --help           list every step

  docs/WIKI.md               the single-page guide
  examples/README.md         what each example demonstrates
EOF

echo
echo "setup complete."
