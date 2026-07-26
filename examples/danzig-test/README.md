# danzig-test

The VST3 ABI integration harness.

## What it demonstrates

`src/tests.zig` covers the pure-Zig core with 35 unit tests. This binary covers
the other half: it links the built `DanzigGain` plugin, calls its exported
`GetPluginFactory`, and drives the returned object through the raw VST3 C ABI
the way a host does.

The point is that it does not import the plugin's Zig types. It declares its own
copy of the `IPluginFactory` vtable layout, casts the returned pointer to a
struct whose only field is a vtable pointer, and calls through C function
pointers:

```zig
const FactoryObject = extern struct {
    vtbl: *const IPluginFactoryVTable,
};

extern fn GetPluginFactory() ?*anyopaque;

const factory: *FactoryObject = @ptrCast(@alignCast(raw.?));
check(factory.vtbl.countClasses(raw.?) == 1, "countClasses reports one exported class");
```

If the plugin ever stops putting the vtable pointer in the first machine word,
that dereference fails here rather than inside a DAW.

The checks run the whole plugin lifecycle through the C ABI:

- The module entry point (`bundleEntry`) accepts the load.
- The factory: `GetPluginFactory`, `countClasses`, `getFactoryInfo`,
  `getClassInfo`, and `queryInterface` refusing an unknown IID without handing
  back a garbage pointer.
- `createInstance` refuses an unknown class id and builds a real object for the
  advertised one, and that object counts references and hands back
  `IAudioProcessor` and `IEditController` as distinct interface pointers.
- The component reports one input and one output bus with two channels and
  named buses; the controller exposes the gain and bypass parameters and round
  trips a parameter display string.
- The processing path: `setupProcessing` at 48 kHz, `setActive`,
  `setProcessing`, and a `process` call whose output is checked against the DSP,
  0 dB passing DC at unity, +6 dB scaling by ~1.995, and bypass passing the
  input through untouched.
- `terminate`, then releasing the last reference drops the count to zero.
- The linked static library still converts dB correctly and the `ParamStore`
  reaches full scale.

## Run

From the repository root:

```bash
zig build test-integration
```

```
danzig integration harness

VST3 module entry
  ok    bundleEntry accepts the load and reports success

VST3 factory ABI
  ok    GetPluginFactory returns a non-null object
  ok    countClasses reports one exported class
  ...
  ok    createInstance accepts the advertised class id
  ok    createInstance writes a non-null object
  ok    the object hands back IAudioProcessor
  ok    the object hands back IEditController
  ...
  ok    setupProcessing accepts 48 kHz
  ok    process returns kResultOk
  ok    the default 0 dB setting passes DC through at unity
  ok    a +6 dB gain setting scales DC by ~1.995
  ok    bypass passes the input through untouched
  ok    releasing the last reference drops the count to zero

danzig static library
  ok    AudioBuffer reports its geometry
  ok    dBToLinear(0 dB) is unity
  ok    dBToLinear(+6 dB) is ~1.995
  ok    ParamStore reaches +48 dB at full scale

all integration checks passed
```

The run has about fifty checks; the full list prints when you run it.

It exits non-zero if any check fails.

## Run it with the unit tests

```bash
zig build test --summary all
```

```
Build Summary: 9/9 steps succeeded; 35/35 tests passed
```

The 35 counts the unit tests in `src/tests.zig`. This harness is a separate run
step, so its failures surface as a failed build step rather than a failed test
count.

## Run the binary directly

```bash
zig build
./zig-out/bin/danzig_test
echo "exit=$?"
```

```
exit=0
```

## What it does not check

It exercises 32-bit processing on mono and stereo, which is what the plugin
supports. It does not drive 64-bit processing or an editor view, both of which
the plugin declines on purpose (`canProcessSampleSize` refuses 64-bit and
`createView` returns null for the host's generic editor). The full host-side
validation, including automation and state round-trips under a real host, is
what `pluginval` covers; see [docs/WIKI.md](../../docs/WIKI.md#current-state).

---

See [docs/WIKI.md](../../docs/WIKI.md) for the testing section.
