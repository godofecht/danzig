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

The checks:

- `GetPluginFactory` returns a non-null object.
- `countClasses` reports one exported class.
- `addRef` and `release` move the reference count by exactly one.
- `queryInterface` for an unknown IID reports failure instead of handing back a
  garbage pointer.
- `getFactoryInfo` and `getClassInfo(0)` return `kResultOk`.
- The linked static library still converts dB correctly and the `ParamStore`
  reaches full scale.

## Run

From the repository root:

```bash
zig build test-integration
```

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

It does not create a plugin instance, because `createInstance` in
`examples/danzig-gain` does not yet produce one. When that is implemented, the
natural next checks are `setupProcessing`, `setActive`, and a `process` call
against a known input buffer.

---

See [docs/WIKI.md](../../docs/WIKI.md) for the testing section.
