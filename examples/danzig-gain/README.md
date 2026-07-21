# danzig-gain

The gain plugin. This is the source that gets compiled for both architectures
and packaged into `DanzigGain.vst3`.

## What it demonstrates

A step up from `../danzig-minimal`. Where the minimal example uses the
lock-free `ParamStore`, this one uses the heap-backed `Plugin` and
`ParameterMap` types from `src/plugin.zig`, and it writes out a VST3 factory
with a real vtable.

**Plugin lifecycle.** `init`, `deinit`, `setupProcessing(sampleRate)`,
`activate`, `deactivate`. The host drives these in order, and `process` passes
audio through unchanged until `activate` has been called.

**A parameter with a plain range.** A `danzig.Parameter` with id 0, titled
"Gain", in units of dB, spanning -48 to +48. `setParameterNormalized`
denormalizes the incoming `[0, 1]` value and pushes the result into the
`GainProcessor`.

**Gain staging with a ramp.** `danzig.GainProcessor` converts dB to linear and
interpolates toward the target rather than stepping, so parameter moves do not
click.

**A VST3 factory.** `PluginFactory` is an `extern struct` whose first field is a
pointer to a static `IPluginFactoryVTable`. `GetPluginFactory` returns its
address. A host reads the first machine word as the vtable pointer and calls
through it, which is exactly the C++ object layout the SDK expects.

## Build

From the repository root:

```bash
zig build
```

Produces `zig-out/lib/libDanzigGain.dylib` for your native architecture.

## Package as a VST3 bundle

```bash
zig build vst3
lipo -info zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

```
Architectures in the fat file: zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain are: x86_64 arm64
```

The bundle:

```bash
find zig-out/DanzigGain.vst3 -type f
```

```
zig-out/DanzigGain.vst3/Contents/Info.plist
zig-out/DanzigGain.vst3/Contents/PkgInfo
zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

## Install

```bash
zig build install-vst3
```

Removes any previous copy and writes a fresh one to
`~/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3`. macOS only.

Verify:

```bash
lipo -info ~/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3/Contents/MacOS/DanzigGain
```

```
Architectures in the fat file: /Users/you/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3/Contents/MacOS/DanzigGain are: x86_64 arm64
```

## What a host currently does with it

Finds the bundle, finds the entry point, and reports zero instantiable classes.
`factory_getClassInfo` writes nothing into the host's buffer and
`factory_createInstance` returns without producing an object, so there is
nothing for the host to load.

```bash
/Applications/pluginval.app/Contents/MacOS/pluginval \
  --validate zig-out/DanzigGain.vst3 --strictness-level 5 --timeout-ms 20000
```

```
Num plugins found: 0
!!! Test 1 failed: No types found.
FAILED!!  1 test failed, out of a total of 1
```

The parts that do work are verifiable. The symbol is exported:

```bash
nm -gU zig-out/DanzigGain.vst3/Contents/MacOS/DanzigGain | grep -i factory
```

```
00000000000004c8 T _GetPluginFactory
```

The bundle is ad-hoc signed by the linker:

```bash
codesign -dvv zig-out/DanzigGain.vst3
```

```
Format=bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20400 size=242 flags=0x20002(adhoc,linker-signed) hashes=4+0 location=embedded
Signature=adhoc
```

And the factory answers the ABI calls a host makes first. `../danzig-test`
checks that on every `zig build test`.

Finishing the plugin means populating `getClassInfo` with a `PClassInfo` and
returning real `IComponent` and `IAudioProcessor` objects from `createInstance`.
The interface declarations are already in `src/vst3.zig`.

## Files

- `root.zig`. The plugin, the factory, and the entry point.

---

See [docs/WIKI.md](../../docs/WIKI.md) for how the bundle is built and what the
factory contract is.
