# danzig

[![CI](https://github.com/godofecht/danzig/actions/workflows/ci.yml/badge.svg)](https://github.com/godofecht/danzig/actions/workflows/ci.yml)
[![Zig](https://img.shields.io/badge/zig-0.14.1%20%7C%200.15.2-f7a41d)](https://ziglang.org/)

A VST3 plugin framework in pure Zig. No JUCE, no Steinberg SDK, no C++ in the
core. `src/vst3.zig` implements the VST3 C ABI directly as `extern struct`s of
`callconv(.c)` function pointers, which is what a C++ vtable is at the machine
level.

**[Read the guide: docs/WIKI.md](docs/WIKI.md)**

## Setup

```bash
git clone https://github.com/godofecht/danzig
cd danzig
./setup.sh
```

`setup.sh` checks your Zig version, builds, runs the tests, packages the
universal VST3 bundle, and prints where it landed. It exits non-zero on failure
and is safe to run repeatedly. Pass `--release` for a `ReleaseFast` build.

By hand:

```bash
zig build                     # Build Summary: 29/29 steps succeeded
zig build test --summary all  # Build Summary: 9/9 steps succeeded; 35/35 tests passed
zig build vst3                # universal arm64 + x86_64 bundle in zig-out/
zig build install-vst3        # copy it to ~/Library/Audio/Plug-Ins/VST3/
```

Then:

```bash
lipo -info zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

```
Architectures in the fat file: zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain are: x86_64 arm64
```

## Requirements

- Zig 0.14.1 or 0.15.2. Both are tested in CI on every push.
- macOS for the VST3 bundle, `install-vst3`, and the GUI example. The library,
  the unit tests, and the CLI examples are portable Zig.
- Xcode command line tools, for `lipo` and the macOS SDK.

## What's here

### Core library (`src/`)

| File | Contents |
|---|---|
| `vst3.zig` | The VST3 C ABI: `IUnknown`, `IPluginBase`, `IComponent`, `IAudioProcessor`, `IEditController`, and the structs they pass. |
| `plugin.zig` | Plugin lifecycle and a heap-backed `ParameterMap`. |
| `audio.zig` | `dBToLinear`, `GainProcessor`, `SimpleRamp`, `AudioBuffer`. |
| `params.zig` | Lock-free `AtomicParam` and `ParamStore(N)`. One cache line per parameter, no heap, no locks. |
| `tests.zig` | 35 unit tests. |

### Examples (`examples/`)

| Example | Run it |
|---|---|
| [danzig-minimal](examples/danzig-minimal/). The smallest complete plugin, and the file to copy. | `zig build run-minimal` |
| [danzig-gain](examples/danzig-gain/). The plugin packaged into the `.vst3` bundle. | `zig build vst3` |
| [danzig-test](examples/danzig-test/). Drives the built plugin through the raw VST3 C ABI. | `zig build test-integration` |
| [danzig-gain-standalone](examples/danzig-gain-standalone/). Offline WAV gain processing. | `zig build run-standalone` |
| [danzig-webui](examples/danzig-webui/). An HTTP server in pure `std.net`. | `./zig-out/bin/danzig-webui` |
| [danzig-gain-ui](examples/danzig-gain-ui/). Native macOS window, WebView plus CoreAudio. | `zig build run-gui` |

See [examples/README.md](examples/README.md) for the index.

## Build artifacts

`zig build` installs:

```
zig-out/
├── bin/
│   ├── danzig-minimal              offline demo of the minimal plugin
│   ├── danzig-gain-standalone      WAV gain processor
│   ├── danzig-webui                HTTP server for the web UI
│   ├── danzig-gain-ui              native window (macOS)
│   └── danzig_test                 VST3 ABI integration harness
└── lib/
    ├── libDanzigGain.dylib         gain plugin, native arch
    ├── libDanzigGain_arm64.dylib   gain plugin, arm64
    ├── libDanzigGain_x86.dylib     gain plugin, x86_64
    └── libDanzigMinimal.dylib      minimal plugin, native arch
```

`zig build vst3` adds the bundle:

```
zig-out/DanzigGain.vst3/
└── Contents/
    ├── Info.plist
    ├── PkgInfo
    └── MacOS/
        └── DanzigGain              universal arm64 + x86_64
```

`libdanzig.a` is not installed. The static library is linked into each target
rather than shipped on its own.

Sizes, from `zig build -Doptimize=ReleaseFast`:

| Artifact | Size |
|---|---|
| `DanzigGain.vst3/Contents/MacOS/DanzigGain` | 84 KB (universal) |
| `lib/libDanzigGain.dylib` | 52 KB |
| `lib/libDanzigMinimal.dylib` | 52 KB |
| `bin/danzig-minimal` | 168 KB |
| `bin/danzig-gain-standalone` | 288 KB |
| `bin/danzig-gain-ui` | 572 KB |

The default Debug build produces the same artifacts at roughly 1 to 2 MB each.

## Current state

The core library, the tests, the build pipeline, and the non-plugin examples all
work. The VST3 factory in `examples/danzig-gain` is a stub: `getClassInfo` and
`createInstance` do not yet produce a class or an object, so a host scans the
bundle and reports zero plugins. See
[Current state](docs/WIKI.md#current-state) for the detail and for what
finishing it involves.

## Documentation

- **[docs/WIKI.md](docs/WIKI.md)**. The single-page guide. Architecture,
  quickstart, parameters, audio helpers, bundle packaging, testing,
  troubleshooting.
- [docs/INDEX.md](docs/INDEX.md). The older multi-page docs.

## License

MIT. See [LICENSE](LICENSE).

VST is a trademark of Steinberg Media Technologies GmbH. danzig vendors no
Steinberg SDK code, and shipping plugins in VST3 format is governed by
Steinberg's own terms, independently of danzig's MIT license.
