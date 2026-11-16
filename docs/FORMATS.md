# Plugin formats

Danzig's DSP is host-neutral Zig. The VST3 and CLAP adapters share
`examples/danzig-gain/dsp.zig`; the CLAP ABI declarations live in
`src/clap.zig`. The CLAP example implements its factory, stereo ports, gain and
bypass parameters, sample-timed automation and state persistence. Hosts provide
generic parameter controls; no custom CLAP editor is claimed.

## CLAP

Build and test the CLAP adapter on a supported target with `zig build` and
`zig build test-clap`. On macOS, package and install the universal bundle:

```sh
zig build clap
zig build test-clap
zig build install-clap
```

The bundle is `zig-out/DanzigGain.clap`. Install it to
`~/Library/Audio/Plug-Ins/CLAP` or `/Library/Audio/Plug-Ins/CLAP` on macOS.
The plugin identifier is `dev.superelectric.danzig.gain`, which must remain
stable across releases. Before shipping, validate using clap-validator and
a real host such as REAPER.

## Audio Unit v2

AUv2 is produced by [clap-wrapper](https://github.com/free-audio/clap-wrapper),
which hosts the CLAP implementation rather than duplicating the audio/parameter
protocol. The wrapper registers as an **effect** (`aufx`), not an instrument
(`aumu`), with subtype `DzGn` and manufacturer code `SuEl`.

On macOS, install Zig, CMake and Xcode command-line tools, then clone
[free-audio/clap](https://github.com/free-audio/clap),
[free-audio/clap-wrapper](https://github.com/free-audio/clap-wrapper), and
[apple/AudioUnitSDK](https://github.com/apple/AudioUnitSDK).

```sh
export CLAP_WRAPPER_SOURCE="$HOME/src/clap-wrapper"
export CLAP_SDK_ROOT="$HOME/src/clap"
export AUDIOUNIT_SDK_ROOT="$HOME/src/AudioUnitSDK"
bash scripts/build-wrappers.sh
```

The `DanzigGain.component` bundle is produced under `zig-out/format-wrappers`.
Copy it into `~/Library/Audio/Plug-Ins/Components/`, sign as appropriate
and run `auval -v aufx DzGn SuEl` after registration. The AUv2 build requires
external SDKs and is intentionally not part of `zig build`.

## AAX

The same clap-wrapper project supports an optional AAX target, using Avid's
separately licensed AAX SDK. On macOS, set `AAX_SDK_ROOT` and opt in:

```sh
export DANZIG_BUILD_AAX=ON
export AAX_SDK_ROOT="$HOME/src/aax"
bash scripts/build-wrappers.sh
```

This can produce a `DanzigGain.aaxplugin` wrapper if the SDK and toolchain
support it. It is **not** automatically a Pro Tools-loadable release: Avid
developer terms, Avid/PACE signing, and validation in Pro Tools are still
required. Pro Tools testing also needs an iLok account. No AAX SDK sources
or signing credentials are committed to the repository.

## Verification matrix

| Format | Build | Verification |
|---|---|---|
| VST3 | `zig build vst3` | Existing VST3 C ABI harness |
| CLAP | `zig build clap` | CLAP factory, parameters and processing harness |
| AUv2 | `bash scripts/build-wrappers.sh` | Requires AudioUnitSDK, macOS and `auval` |
| AAX | `DANZIG_BUILD_AAX=ON bash scripts/build-wrappers.sh` | Requires Avid SDK, signing and Pro Tools |

These external wrappers are not a claim of independent native Zig AU or AAX
implementations. Danzig and clap-wrapper are MIT licensed; Apple AudioUnitSDK
and Avid AAX SDK have independent licences and redistribution requirements.
