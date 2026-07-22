# danzig

A VST3 plugin framework written in pure Zig. No JUCE. No Steinberg SDK. No C++
at all in the core.

Source: [github.com/godofecht/danzig](https://github.com/godofecht/danzig)

---

## Contents

- [What danzig is](#what-danzig-is)
- [Current state](#current-state)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
- [The parameter system](#the-parameter-system)
- [The audio helpers](#the-audio-helpers)
- [Building the universal VST3 bundle](#building-the-universal-vst3-bundle)
- [Testing](#testing)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Licensing and trademarks](#licensing-and-trademarks)

---

## What danzig is

VST3 is a C ABI dressed up as COM. A plugin is a shared library exporting one
symbol, `GetPluginFactory`. The host calls it, reads the first machine word of
the returned pointer as a vtable pointer, and calls through that vtable to
discover classes, create objects, and push audio buffers.

That contract is small. It is also the only part of Steinberg's SDK a plugin
strictly needs. Everything else in the SDK is C++ scaffolding around it.

danzig implements the contract directly in Zig. `src/vst3.zig` declares the
interfaces as `extern struct`s of `callconv(.c)` function pointers, which is
exactly what a C++ vtable is at the machine level. A plugin fills in the
function pointers and returns a pointer to the struct. The host cannot tell the
difference.

The reasons to do this rather than use JUCE:

**Fast builds.** A clean build of the library, five example binaries, and both
architectures of the plugin takes about 5.6 seconds on an M-series Mac. A
no-change rebuild takes 0.6 seconds, and packaging the universal bundle on top
of a warm cache takes 0.5 seconds. There is no CMake step and no dependency
tree.

**One binary format decision, made explicitly.** The bundle layout, the
`Info.plist`, and the `lipo` invocation are twenty lines of `build.zig` you can
read. Nothing is hidden behind a framework's packaging step.

**Allocation is visible.** Zig has no hidden allocations and no destructors that
run at surprising times. On the audio thread that matters. The parameter store
in `src/params.zig` is a fixed array of atomics with no heap involvement at all,
which you can verify by reading 160 lines.

**Cross-compilation is free.** Zig builds `x86_64-macos` from an arm64 machine
with no extra toolchain. That is what makes the universal bundle a build step
rather than a CI matrix: `build.zig` compiles the plugin for both architectures
and merges them with `lipo`, on whichever machine you happen to be on.

macOS is the only supported platform today. The VST3 bundle layout, the
`install-vst3` step, and the GUI example are all macOS-specific. The library,
the unit tests, and the command-line examples are portable Zig and should build
anywhere Zig runs, though only macOS is tested.

---

## Current state

Honest summary, because the difference matters if you are choosing a framework.

**Working and tested.**

- The core library: `vst3.zig`, `plugin.zig`, `audio.zig`, `params.zig`.
- 35 unit tests covering dB conversion, ramps, buffers, and the atomic
  parameter store.
- An integration harness that links the built plugin, calls its exported
  `GetPluginFactory`, and drives the returned object through the raw C ABI.
- A universal arm64 + x86_64 `.vst3` bundle that installs into the macOS plugin
  folder and is ad-hoc signed by the linker.
- Three runnable non-plugin examples: an offline WAV processor, an HTTP server
  serving the web UI, and a native window with an embedded WebView and
  CoreAudio device enumeration.

**Not finished.**

The factory in `examples/danzig-gain` is a stub. `countClasses` returns 1, but
`getClassInfo` writes nothing into the host's buffer and `createInstance`
returns without producing an object. A host therefore scans the bundle, finds
the entry point, and reports zero usable classes:

```bash
/Applications/pluginval.app/Contents/MacOS/pluginval \
  --validate zig-out/DanzigGain.vst3 --strictness-level 5 --timeout-ms 20000
```

```
Started validating: .../danzig/zig-out/DanzigGain.vst3
Random seed: 0x6afa9d8
Validation started
Strictness level: 5
-----------------------------------------------------------------
Starting tests in: pluginval / Scan for plugins located in: .../DanzigGain.vst3...
Num plugins found: 0
!!! Test 1 failed: No types found. This usually means the plugin binary is missing
or damaged, an incompatible format or that it is an AU that isn't found by macOS
so can't be created.
FAILED!!  1 test failed, out of a total of 1
FAILURE
*** FAILED
```

Completing it means filling in `getClassInfo` with a populated `PClassInfo`
(class ID, cardinality, category string, name) and having `createInstance`
return objects implementing `IComponent`, `IAudioProcessor`, and
`IEditController`. The interface declarations for all three already exist in
`src/vst3.zig`. The wiring does not.

So: use danzig today as a DSP and parameter library with a working VST3 build
pipeline. The last mile into a DAW is the open work.

---

## Architecture

### COM in Zig

A C++ object with virtual functions is a pointer to a vtable followed by the
object's fields. A COM interface is that, plus the convention that the first
three vtable slots are `queryInterface`, `addRef`, and `release`.

`src/vst3.zig` writes this out as plain Zig:

```zig
pub const IUnknown = extern struct {
    queryInterface: *const fn (?*IUnknown, *const IID, ?*[*]?*anyopaque) callconv(.c) TResult = undefined,
    addRef: *const fn (?*IUnknown) callconv(.c) u32 = undefined,
    release: *const fn (?*IUnknown) callconv(.c) u32 = undefined,
};
```

Three things make this work.

`extern struct` guarantees C layout: fields in declaration order, C alignment
rules, no reordering. This is the whole reason the trick is safe.

`callconv(.c)` gives each function pointer the platform C calling convention,
so arguments land in the registers the host expects.

Interface inheritance becomes struct embedding. `IComponent` starts with an
`IPluginBase` field, which starts with an `IUnknown` field. Because `extern
struct` puts fields at ascending offsets with the first at offset zero, a
`*IComponent` is bit-identical to a `*IPluginBase` and to a `*IUnknown`. That
is exactly what single inheritance produces in C++.

```zig
pub const IComponent = extern struct {
    pluginBase: IPluginBase,      // offset 0, itself starting with IUnknown
    getControllerClassId: *const fn (?*IComponent, ?*CUID) callconv(.c) TResult = undefined,
    setIoMode: ...
};
```

The rest of `vst3.zig` is the data the ABI passes around: `ProcessData`,
`AudioBusBuffers`, `ProcessSetup`, `ParameterInfo`, `BusInfo`, plus the
`TResult` constants and bus and media type enums. All `extern struct`, all
laid out to match the SDK headers.

### How a plugin is registered

A VST3 binary exports one symbol. That is the entire registration mechanism.

```zig
export fn GetPluginFactory() ?*anyopaque {
    gFactory.vtbl = @ptrCast(&factoryVtable);
    return @ptrCast(&gFactory);
}
```

`gFactory` is a static whose first field is a pointer to a static vtable. The
host receives the address of `gFactory`, reads the first word to get
`&factoryVtable`, and calls through it. Nothing is allocated. Nothing is
registered anywhere else. There is no plugin database, no manifest, and no
macro.

From there the host does:

1. `countClasses()` to learn how many classes the binary exports.
2. `getClassInfo(i, &info)` for each, reading the class ID, category, and name.
3. `createInstance(class_id, iid, &out)` to get an object implementing the
   requested interface.

`examples/danzig-test` performs exactly steps 1 through 3 against the built
plugin, going through the C function pointers rather than through Zig types, so
a layout change that would break a real host breaks the test first.

### The audio callback path

The host owns the buffers. It hands you a `ProcessData` describing them and
expects you to be finished by the time the callback returns.

```
host audio thread
  |
  +-- IAudioProcessor.setupProcessing(&setup)   once, before playback
  |      sample rate, max block size, 32- or 64-bit samples
  |
  +-- IAudioProcessor.setProcessing(true)       transport starts
  |
  +-- IAudioProcessor.process(&data)            every block, on the audio thread
  |      data.numSamples
  |      data.inputs[bus].channelBuffers32[ch]
  |      data.outputs[bus].channelBuffers32[ch]
  |
  +-- IAudioProcessor.setProcessing(false)      transport stops
```

Inside `process` the rules are the usual real-time rules. No allocation, no
locks, no file or network access, no logging that touches a mutex. danzig's
contribution is that the parameter path obeys them by construction: the host's
UI thread writes a normalized `f32` with an atomic store, and the audio thread
reads it with an atomic load. There is nothing between the two that can block.

A minimal per-sample loop looks like this, from
`examples/danzig-minimal/root.zig`:

```zig
pub fn process(
    self: *MinimalPlugin,
    input: []const []const f32,
    output: []const []f32,
    frames: usize,
) void {
    for (0..frames) |i| {
        const gain = danzig.dBToLinear(self.params.tick(ParamIndex.trim));
        for (input, output) |in_ch, out_ch| {
            out_ch[i] = in_ch[i] * gain;
        }
    }
}
```

`tick` advances the smoother by one sample and returns the plain value, so a
parameter change becomes a ramp rather than a step. That is what stops a slider
drag from producing clicks.

---

## Prerequisites

- **Zig 0.14.1 or 0.15.2.** Both are tested in CI on every push. The sources
  use spellings valid in both: the `root_module` build API, `callconv(.c)`,
  and `net.Stream.read`. Other versions may work and are unsupported.
- **macOS** for the VST3 bundle, the `install-vst3` step, and the GUI example.
- **Xcode command line tools**, for `lipo` and the macOS SDK.
- **A VST3 host** if you want to scan the bundle.

Nothing else. There is no CMake, no vendored SDK, and one optional Zig
dependency (`webview`) that is fetched lazily and only when you build the GUI
example.

Install Zig with Homebrew or from ziglang.org:

```bash
brew install zig                # currently 0.15.2
# or download 0.14.1 / 0.15.2 from https://ziglang.org/download/
```

---

## Quickstart

Five minutes, from clone to an installed bundle.

### 1. Clone and run setup

```bash
git clone https://github.com/godofecht/danzig
cd danzig
./setup.sh
```

`setup.sh` checks your Zig version, builds, runs the tests, builds the universal
bundle, and prints where it landed. It exits non-zero if any of that fails, and
it is safe to run repeatedly. Add `--release` for a `ReleaseFast` build.

If you prefer to do it by hand, the four commands are below.

### 2. Build

```bash
zig build
```

```
Build Summary: 29/29 steps succeeded
```

### 3. Test

```bash
zig build test --summary all
```

```
Build Summary: 9/9 steps succeeded; 35/35 tests passed
```

### 4. Package the bundle

```bash
zig build vst3
lipo -info zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

```
Architectures in the fat file: zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain are: x86_64 arm64
```

### 5. Install it

```bash
zig build install-vst3
```

This removes any previous copy and writes a fresh one to
`~/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3`. Verify it:

```bash
lipo -info ~/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

```
Architectures in the fat file: /Users/you/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3/Contents/MacOS/DanzigGain are: x86_64 arm64
```

### 6. Load it in a DAW

Restart your DAW so it rescans the plugin folder. As of today the scan finds the
bundle and the entry point but reports no instantiable classes, for the reason
described under [Current state](#current-state). The bundle structure, the
universal binary, the `Info.plist`, and the ad-hoc signature are all correct and
verifiable:

```bash
codesign -dvv zig-out/DanzigGain.vst3
```

```
Executable=.../zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain
Identifier=libDanzigGain_arm64.dylib
Format=bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20400 size=242 flags=0x20002(adhoc,linker-signed) hashes=4+0 location=embedded
Signature=adhoc
```

### 7. Hear the DSP without a DAW

```bash
zig build run-minimal
```

```
danzig-minimal: one parameter, one line of DSP

Trim range is -24 to +24 dB, 20 ms smoothing, 48 kHz.

  full cut     normalized 0.00  ->   -24.00 dB  (output 0.0631)
  unity        normalized 0.50  ->     0.00 dB  (output 1.0000)
  full boost   normalized 1.00  ->    24.00 dB  (output 15.8473)

Copy examples/danzig-minimal/root.zig to start your own plugin.
```

That file is the template. Copy it and start editing `process`.

---

## The parameter system

`src/params.zig`. Two types: `AtomicParam` for one value, `ParamStore(N)` for a
fixed set of them.

### The problem

A parameter is written by one thread and read by another. The UI or the host
automation lane writes; the audio callback reads. The audio callback cannot
block, so a mutex is not available. It cannot allocate, so a queue that grows is
not available either.

The value is a single `f32`. A lock-free atomic is sufficient and is the whole
solution.

### AtomicParam

```zig
pub const AtomicParam = extern struct {
    raw: std.atomic.Value(u32) = ...,   // normalized [0, 1], bit-cast from f32
    smoothed: f32 = 0.0,                // audio thread only
    min: f32 = 0.0,
    max: f32 = 1.0,
    default_normalized: f32 = 0.5,
    smooth_coeff: f32 = 0.0,
    _pad: [40]u8 = undefined,           // pad to 64 bytes
};
```

The writer side:

```zig
pub fn setNormalized(self: *Self, value: f32) void {
    const clamped = std.math.clamp(value, 0.0, 1.0);
    self.raw.store(@bitCast(clamped), .release);
}
```

One clamp and one release store. Wait-free. The `f32` is bit-cast to `u32`
because `std.atomic.Value` wants an integer, and a bit-cast of a clamped finite
float is exact.

The reader side runs once per sample:

```zig
pub fn tick(self: *Self) f32 {
    const target = self.getTargetPlain();
    if (self.smooth_coeff <= 0.0) {
        self.smoothed = target;
    } else {
        self.smoothed += (target - self.smoothed) * (1.0 - self.smooth_coeff);
    }
    return self.smoothed;
}
```

`getTargetPlain` does an acquire load, then denormalizes into `[min, max]`. The
one-pole filter that follows turns a step into an exponential approach. The
coefficient comes from a time constant in milliseconds:

```zig
self.smooth_coeff = @exp(-1000.0 / (ms * sample_rate));
```

`smoothed` is deliberately non-atomic. Only the audio thread touches it.

Use `snap()` to jump `smoothed` to the target with no ramp. That is what you
want on preset load or transport relocation, where a ramp would be a glide.

### Why exactly one cache line

`AtomicParam` is padded to 64 bytes and the size is enforced at compile time:

```zig
comptime {
    if (@sizeOf(AtomicParam) != 64) {
        @compileError("AtomicParam must be 64 bytes for cache line alignment");
    }
}
```

Without the padding, several parameters would share a cache line. When the UI
thread stores to parameter 0, the cache coherence protocol invalidates the whole
line on every other core. The audio thread reading parameter 1, which nobody
wrote, would still take a coherence miss. This is false sharing, and it shows up
as jitter in the audio callback rather than as a wrong answer, which makes it
unpleasant to find.

64 bytes is the line size on x86_64 and on Apple Silicon's L1 data cache. One
parameter per line means a store to one parameter never disturbs the read of
another. The cost is 40 wasted bytes per parameter. For 64 parameters that is
2.5 KB of padding, which is nothing against the price of one stalled audio
callback.

The compile-time check exists so that adding a field silently breaks the build
instead of silently reintroducing false sharing.

There is a second, smaller reason for the fixed size. `extern struct` with a
known size means `ParamStore(N)` is a flat `[N]AtomicParam` array, so parameter
`i` is at a computable offset with no indirection.

### ParamStore

```zig
var store = danzig.ParamStore(4){};
const gain = store.add(-48.0, 48.0, 0.5, 20.0, 48000.0);
//                     min    max   default  smooth_ms  sample_rate
```

`add` returns the index and asserts you have not exceeded `N`. Call it during
init only.

| Call | Thread | Notes |
|---|---|---|
| `add(min, max, default, ms, sr)` | init | Returns the index. Asserts on overflow. |
| `setNormalized(i, v)` | host / UI | Ignores an out-of-range index rather than trapping. |
| `getNormalized(i)` | any | Returns 0.0 for an out-of-range index. |
| `tick(i)` | audio | Advances one sample, returns the plain value. |
| `tickAll()` | audio | Advances every registered parameter. |
| `getSmoothed(i)` | audio | Reads the last ticked value. Call after `tick`. |
| `snapAll()` | audio | Jumps every smoothed value to its target. |

The out-of-range behaviour is deliberate. A host sending a stale parameter index
during a preset change should not take down the audio thread.

One gap to know about: `setSampleRate` is currently a no-op. If the sample rate
changes, re-run `setSmoothingMs(ms, new_rate)` on each parameter, or rebuild the
store in `setupProcessing`.

---

## The audio helpers

`src/audio.zig`. Small, dependency-free, and covered by the unit tests.

### dBToLinear and linearTodB

```zig
pub fn dBToLinear(dB: f32) f32 {
    return @exp(dB * 0.11512925464970229);   // ln(10)/20
}

pub fn linearTodB(linear: f32) f32 {
    if (linear <= 0.0) return -80.0;
    return @log(linear) * 8.6858896380650365; // 20/ln(10)
}
```

Both avoid `pow` and `log10` in favour of a single `exp` or `log` and a
multiply. `linearTodB` floors at -80 dB for non-positive input, so silence
returns a finite number rather than negative infinity.

The constants are worth a test of their own, and they have one. A previous copy
of this file carried a stray factor of ten in the exponent, which turned
`dBToLinear(6)` into 1000.0 instead of 1.9953. `src/tests.zig` now checks unity
at 0 dB, the factor of two at +6 dB, the factor of ten at +20 dB, and a full
round trip across -48 to +24 dB.

### GainProcessor

A gain stage with a built-in ramp.

```zig
var g = danzig.GainProcessor{};
g.setGain(6.0);                            // dB
g.process(&inputs, &outputs, channels, frames);
```

`setGain` converts to a linear target. `process` interpolates the current gain
toward the target by a fixed 0.001 per sample, so a change takes roughly a
thousand samples to substantially complete. `setNormalizedGain` maps `[0, 1]`
onto -48 to +48 dB, which is the range the example plugin exposes.

The interpolation coefficient is fixed and not sample-rate aware. For a
rate-independent ramp, use `AtomicParam` with a millisecond time constant
instead.

### SimpleRamp

A linear ramp over a sample count, for anything that is not a gain.

```zig
var r = danzig.SimpleRamp.init(0.0, 8);   // start value, ramp length in samples
r.setTarget(1.0);
for (0..8) |_| _ = r.next();
// r.getValue() == 1.0
```

`setTarget` restarts the ramp from the current value. A ramp length of zero or
one is treated as instant. The final sample is snapped to the target exactly, so
the ramp does not leave a residue.

### AudioBuffer

An owned multi-channel buffer, for offline work and tests. It allocates, so keep
it off the audio thread.

```zig
var buf = try danzig.AudioBuffer.init(allocator, 2, 512, 48000.0);
defer buf.deinit(allocator);
buf.clear();
```

`init` zeroes every channel. `clear` and its alias `silence` re-zero.

---

## Building the universal VST3 bundle

macOS ships on two architectures. A plugin bundle holds one universal binary so
that hosts of either architecture load the same file.

```bash
zig build vst3
```

That step, in `build.zig`, does four things.

**1. Compiles the plugin twice.** Once for `aarch64-macos` and once for
`x86_64-macos`, via `b.resolveTargetQuery`. Zig cross-compiles both from
whichever machine you are on, so no second toolchain is needed.

```zig
const arches = [_]std.Target.Cpu.Arch{ .aarch64, .x86_64 };
const suffixes = [_][]const u8{ "arm64", "x86" };

inline for (arches, suffixes) |arch, suffix| {
    const arch_target = b.resolveTargetQuery(.{ .cpu_arch = arch, .os_tag = .macos });
    // ... build danzig_<suffix> and DanzigGain_<suffix>
    lipo.addArtifactArg(plugin);
}
```

**2. Merges them with `lipo`.** `b.addSystemCommand(&.{ "lipo", "-create" })`
collects both artifacts and writes one fat Mach-O into the build cache. The
output path is a build-graph node, so the merge reruns only when an input
changes.

**3. Lays out the bundle.** `b.addWriteFiles()` builds the directory:

```
DanzigGain.vst3/
  Contents/
    Info.plist          generated from a template in build.zig
    PkgInfo             the 8 bytes "BNDL????"
    MacOS/
      DanzigGain        the universal binary, no file extension
```

The executable carries no extension. That is a bundle requirement, and it is why
the lipo output is copied rather than installed under its library name.

**4. Installs into `zig-out/`.** The result is
`zig-out/DanzigGain.vst3`.

Then:

```bash
zig build install-vst3
```

removes any existing copy and copies the bundle to
`$HOME/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3`, which is where macOS hosts
scan.

The bundle is kept behind its own step rather than the default install because
it doubles the compile work and only applies to macOS.

Sizes, from a `ReleaseFast` build:

| Artifact | Size |
|---|---|
| `zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain` | 84 KB (universal) |
| `zig-out/lib/libDanzigGain.dylib` | 52 KB (arm64) |
| `zig-out/lib/libDanzigMinimal.dylib` | 52 KB (arm64) |
| `zig-out/bin/danzig-minimal` | 168 KB |

The same artifacts in the default Debug build run about 1 to 2 MB each.

---

## Testing

Two suites, one command.

```bash
zig build test --summary all
```

```
Build Summary: 9/9 steps succeeded; 35/35 tests passed
```

### Unit tests

`src/tests.zig`, 35 tests, run with `zig build test-unit`. No artifact and no
host required. They cover:

- dB and linear conversion in both directions, including the round trip and the
  -80 dB floor.
- `linearInterpolate` and `clamp` at endpoints and midpoints.
- `AudioBuffer` init, zeroing, and clear.
- `GainProcessor` dB conversion, normalized mapping, clamping, and that
  `process` ramps rather than jumping.
- `SimpleRamp` instant mode, arrival at target, and restart on `setTarget`.
- `normalize` and `denormalize`, including the degenerate zero-width range.
- `AtomicParam`: the 64-byte size assertion, clamping, denormalization,
  instant mode, monotone non-overshooting smoothing, `snap`, and
  `setSmoothingMs` with non-positive input.
- `ParamStore`: index allocation, round trip, out-of-range tolerance,
  `tickAll`, and `snapAll`.

### VST3 ABI integration harness

`examples/danzig-test`, run with `zig build test-integration`. This one links
the built `DanzigGain` plugin and calls into it the way a host does.

```
danzig integration harness

VST3 factory ABI
  ok    GetPluginFactory returns a non-null object
  ok    countClasses reports one exported class
  ok    addRef/release move the count by exactly one
  ok    queryInterface for an unknown IID reports failure
  ok    getFactoryInfo returns kResultOk
  ok    getClassInfo(0) returns kResultOk

danzig static library
  ok    AudioBuffer reports its geometry
  ok    dBToLinear(0 dB) is unity
  ok    dBToLinear(+6 dB) is ~1.995
  ok    ParamStore reaches +48 dB at full scale

all integration checks passed
```

The harness declares its own copy of the `IPluginFactory` vtable rather than
importing the plugin's Zig types. It reads the first word of the returned
pointer as a vtable pointer and calls through the C function pointers. If the
object layout ever stops matching what a host expects, the dereference fails
here before it fails in a DAW.

It returns a non-zero exit code on failure, so `zig build test` fails with it.

### CI

`.github/workflows/ci.yml` runs `zig build` and `zig build test` on `macos-15`
against both 0.14.1 and 0.15.2. The runner is pinned to `macos-15` rather than
`macos-latest`, because `macos-latest` now ships an Xcode whose SDK Zig 0.14.1
cannot link against.

---

## Examples

Each directory has its own README with the exact commands.

| Example | What it shows | Run it |
|---|---|---|
| `examples/danzig-minimal` | The smallest complete plugin. Start here. | `zig build run-minimal` |
| `examples/danzig-gain` | A fuller plugin: `Plugin`, `ParameterMap`, `GainProcessor`, and a factory vtable. | Built into the `.vst3` bundle |
| `examples/danzig-test` | Driving the plugin through the raw VST3 C ABI. | `zig build test-integration` |
| `examples/danzig-gain-standalone` | Offline WAV processing with the DSP core. | `zig build run-standalone` |
| `examples/danzig-webui` | A pure-`std.net` HTTP server serving the web UI. | `./zig-out/bin/danzig-webui` |
| `examples/danzig-gain-ui` | A native macOS window: WebView UI plus CoreAudio device enumeration. | `zig build run-gui` |

---

## Troubleshooting

### `zig build` fails with undefined libc symbols

Zig 0.14.1 cannot link against the SDK shipped with Xcode 26. Either use Zig
0.15.2 or install an older SDK. Setting `SDKROOT` does not help, because the SDK
itself is the incompatibility.

Check which SDK you have:

```bash
xcodebuild -version
xcrun --show-sdk-path
```

### `lipo -info` reports only one architecture

You looked at `zig-out/lib/libDanzigGain.dylib`, which is the native-only build.
The universal binary is inside the bundle:

```bash
lipo -info zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

If the bundle itself is single-architecture, `zig build vst3` did not run.
`zig build` alone does not produce the bundle.

### The DAW does not list the plugin

Expected today. See [Current state](#current-state). The factory's
`getClassInfo` and `createInstance` are stubs, so a host finds zero classes.
Confirm the bundle is otherwise sound:

```bash
nm -gU zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain | grep -i factory
```

```
00000000000004c8 T _GetPluginFactory
```

### `danzig-webui` starts but the browser shows nothing

The server binds `127.0.0.1:3000`. If something else already holds that port you
will reach the other service instead. Check with:

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

The port is a constant in `examples/danzig-webui/root.zig`. Change it and
rebuild.

### `danzig-webui` exits with an error about `ui/index.html`

It reads the UI from a relative path at startup, so it has to be run from the
repository root:

```bash
cd /path/to/danzig
./zig-out/bin/danzig-webui
```

### `danzig-gain-standalone` rejects the input file

It handles 32-bit float PCM WAV only, with a canonical 44-byte header. Anything
else gives `Only 32-bit float PCM WAV files are supported`. To make a test file
without extra tools:

```bash
python3 - <<'PY'
import struct, math
sr, n, ch = 48000, 48000, 1
data = b''.join(struct.pack('<f', 0.5 * math.sin(2 * math.pi * 440 * i / sr)) for i in range(n))
hdr = struct.pack('<4sI4s4sIHHIIHH4sI', b'RIFF', 36 + len(data), b'WAVE', b'fmt ',
                  16, 1, ch, sr, sr * ch * 4, ch * 4, 32, b'data', len(data))
open('sine.wav', 'wb').write(hdr + data)
PY
```

### The GUI example does not build

It needs the `webview` dependency, which Zig fetches lazily. Run `zig build`
once with a network connection. On macOS it also links `CoreAudio` and
`CoreFoundation`, so the command line tools must be installed.

### `zig build -Dtarget=...` fails on `webviewStatic`

```
error: unable to find framework 'WebKit'. searched paths:  none
```

The GUI example's `webview` dependency is C++ and links WebKit, which does not
cross-compile. The Zig code does cross-compile fine, which is why
`zig build vst3` produces both architectures. Build the library and the
non-GUI examples for another target directly, or build natively.

### `AtomicParam must be 64 bytes for cache line alignment`

You added or resized a field in `AtomicParam` without adjusting `_pad`. Shrink
`_pad` by the number of bytes you added. The check is there on purpose. See
[Why exactly one cache line](#why-exactly-one-cache-line).

### A parameter change clicks

The parameter has no smoothing. Pass a non-zero `smooth_ms` to `add`:

```zig
_ = store.add(-24.0, 24.0, 0.5, 20.0, sample_rate);
//                                ^^^^ 20 ms one-pole ramp
```

Then read it with `tick` inside the per-sample loop rather than once per block.

---

## Licensing and trademarks

danzig is MIT licensed. See [LICENSE](../LICENSE).

danzig vendors no Steinberg SDK code. `src/vst3.zig` is a hand-written Zig
description of the VST3 C ABI, derived from the published interface layouts.

VST is a trademark of Steinberg Media Technologies GmbH, registered in Europe
and other countries. Distributing plugins in VST3 format is governed by
Steinberg's own licensing terms, which apply to you independently of danzig's
MIT license. Read them before you ship anything.

---

Source, issues, and the CI matrix:
[github.com/godofecht/danzig](https://github.com/godofecht/danzig)
