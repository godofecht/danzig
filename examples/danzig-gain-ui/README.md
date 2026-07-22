# danzig-gain-ui

A native macOS window with an embedded WebView and real CoreAudio device
enumeration.

macOS only.

## What it demonstrates

The same `ui/index.html` that `../danzig-webui` serves over HTTP, rendered in a
native window with no server in between.

**HTML embedded at build time.** `build.zig` adds the file as an anonymous
import and `root.zig` pulls it in with `@embedFile`, so the binary is
self-contained:

```zig
const UI_HTML: [:0]const u8 = @embedFile("ui_html");
```

```zig
gui.root_module.addAnonymousImport("ui_html", .{ .root_source_file = b.path("ui/index.html") });
```

**Data injected before the page loads.** The device list is serialized to JSON
and evaluated as a global before the HTML is set, so the page can read
`window.__audioDevices` on first paint rather than fetching it:

```zig
const init_js = std.fmt.bufPrintZ(&init_js_buf, "window.__audioDevices = {s};", .{json});
try wv.init(init_js);
try wv.setHtml(UI_HTML);
```

**CoreAudio through `@cImport`.** `coreaudio.zig` calls
`AudioObjectGetPropertyData` directly, reads device names as `CFStringRef` and
converts them to UTF-8, and counts input and output channels. No wrapper
library. The C header comes straight in:

```zig
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
});
```

**Linking a C++ dependency.** The `webview` Zig package is declarations only.
The implementation is its C++ core, exposed as a static library, plus the macOS
frameworks:

```zig
gui.linkLibrary(webview_dep.artifact("webviewStatic"));
gui.linkFramework("CoreAudio");
gui.linkFramework("CoreFoundation");
```

## Build and run

From the repository root:

```bash
zig build run-gui
```

Or build first and run the binary:

```bash
zig build
./zig-out/bin/danzig-gain-ui
```

```
DanzigGain standalone app running.
```

A 600x700 fixed window titled "DanzigGain" opens with the gain UI in it.

## Requirements

- macOS, with the Xcode command line tools installed for the WebKit and
  CoreAudio frameworks.
- A network connection on the first build. `webview` is a lazy dependency, so
  Zig fetches it the first time this target is built. The pinned commit and hash
  are in `build.zig.zon`.

## Notes

The target is wired up only when the dependency resolves and only on macOS, so
`zig build` on other platforms skips it rather than failing:

```zig
if (target.result.os.tag == .macos) {
    if (b.lazyDependency("webview", .{ .target = target, .optimize = optimize })) |webview_dep| {
        addGuiExample(b, target, optimize, danzig_module, danzig_lib, webview_dep);
    }
}
```

Cross-compiling this target does not work. `webviewStatic` links WebKit, and
`zig build -Dtarget=x86_64-macos` fails with `unable to find framework
'WebKit'`. The pure-Zig targets cross-compile fine, which is what the universal
VST3 bundle relies on.

The window is a viewer today. The slider does not yet drive
`danzig.GainProcessor`, and no audio device is opened.

## Files

- `root.zig`. Window creation, JS injection, and the run loop.
- `coreaudio.zig`. Device enumeration and JSON serialization.
- `../../ui/index.html`. The page, shared with `../danzig-webui`.

---

See [docs/WIKI.md](../../docs/WIKI.md) for the rest of the project.
