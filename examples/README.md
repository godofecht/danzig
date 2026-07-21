# danzig examples

Six directories. Start with `danzig-minimal`.

Every command below is run from the repository root.

| Directory | What it demonstrates | Command |
|---|---|---|
| [danzig-minimal](danzig-minimal/) | The smallest complete plugin. The file to copy. | `zig build run-minimal` |
| [danzig-gain](danzig-gain/) | A fuller plugin, and the source of the `.vst3` bundle. | `zig build vst3` |
| [danzig-test](danzig-test/) | Driving the built plugin through the raw VST3 C ABI. | `zig build test-integration` |
| [danzig-gain-standalone](danzig-gain-standalone/) | Offline WAV processing with the DSP core. | `zig build run-standalone` |
| [danzig-webui](danzig-webui/) | An HTTP server in pure `std.net` serving the web UI. | `./zig-out/bin/danzig-webui` |
| [danzig-gain-ui](danzig-gain-ui/) | A native macOS window: WebView plus CoreAudio. | `zig build run-gui` |

Build everything at once:

```bash
zig build
```

```
Build Summary: 29/29 steps succeeded
```

List every step:

```bash
zig build --help
```

```
Steps:
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  run-minimal                  Run the minimal plugin template offline
  run-standalone               Run the standalone audio processor
  vst3                         Build and package the universal VST3 bundle
  install-vst3                 Install the VST3 bundle to ~/Library/Audio/Plug-Ins/VST3/
  run-gui                      Run the standalone GUI app
  test-unit                    Run unit tests only
  test-integration             Run VST3 ABI integration tests only
  test                         Run tests
```

## Which one do I copy?

Copy `danzig-minimal/root.zig`. It has one parameter, one line of DSP, and the
one symbol a VST3 host looks for, with the rest of the file given over to
comments explaining each part.

`danzig-gain` is the next step up. It adds the heap-backed `ParameterMap`, the
`GainProcessor`, and a factory with a real vtable behind it.

## Not wired into the build

Two files are leftovers from an earlier layout and are not referenced by
`build.zig`:

- `examples/root.zig` is an older copy of `danzig-gain/root.zig`.
- `examples/danzig-gain-webui/root.zig` is a stub that predates
  `danzig-webui`.

Neither is compiled or tested. Ignore them.

---

See [docs/WIKI.md](../docs/WIKI.md) for the full guide.
