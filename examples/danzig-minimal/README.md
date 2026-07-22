# danzig-minimal

The smallest complete danzig plugin. Copy this to start your own.

## What it demonstrates

One file, about 120 lines, most of them comments. It shows the four pieces every
danzig plugin needs and nothing else.

**A parameter store.** `danzig.ParamStore(1)` holds one trim control spanning
-24 to +24 dB with a 20 ms one-pole smoother. The store is a fixed array of
cache-line-sized atomic slots, so registering a parameter allocates nothing and
reading one from the audio thread cannot block.

**A writer path.** `setParameter` does a single atomic store. This is what the
host or the UI calls, on its own thread, at any time.

**An audio callback.** `process` reads the smoothed value once per sample with
`tick`, converts it to a linear gain, and multiplies. No allocation, no locks,
no branches on parameter state. Per-sample smoothing is what stops a slider drag
from clicking.

**The VST3 entry point.** `export fn GetPluginFactory()` is the only symbol a
host looks for in the binary. Here it returns null, which a host reads as "this
binary exports no classes". See `../danzig-gain` for a factory with a vtable
behind it.

The same source builds twice: as the shared library a host would load, and as an
executable, so the DSP can be run and checked without a DAW.

## Build and run

From the repository root:

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

The demo feeds 500 ms of full-scale DC through the plugin at three trim
settings and reads the level off the last sample. DC makes the gain readable
directly. 500 ms is well past the 20 ms smoother's settling time, which is why
the numbers land on exactly -24, 0, and +24 dB.

## Artifacts

```bash
zig build
ls zig-out/lib/libDanzigMinimal.dylib zig-out/bin/danzig-minimal
```

```
zig-out/bin/danzig-minimal
zig-out/lib/libDanzigMinimal.dylib
```

`libDanzigMinimal.dylib` is the plugin. `danzig-minimal` is the offline demo
above.

## Starting your own plugin

```bash
mkdir -p examples/my-plugin
cp examples/danzig-minimal/root.zig examples/my-plugin/root.zig
```

Then add it to `build.zig` next to the `danzig_minimal` block, changing the
names:

```zig
const my_plugin = b.addLibrary(.{
    .name = "MyPlugin",
    .root_module = b.createModule(.{
        .root_source_file = b.path("examples/my-plugin/root.zig"),
        .target = target,
        .optimize = optimize,
    }),
    .linkage = .dynamic,
});
my_plugin.root_module.addImport("danzig", danzig_module);
my_plugin.linkLibrary(danzig_lib);
b.installArtifact(my_plugin);
```

Edit `process`. Add parameters by widening `ParamStore(1)` and calling `add`
once more in `init`.

---

See [docs/WIKI.md](../../docs/WIKI.md) for the parameter system and the audio
callback path in full.
