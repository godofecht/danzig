const std = @import("std");

const VERSION = "0.1.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Danzig library (static)
    const danzig_lib = b.addLibrary(.{
        .name = "danzig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // Danzig module for import by other targets
    const danzig_module = b.addModule("danzig", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Danzig gain VST3 plugin (shared, embeds danzig)
    const danzig_gain = b.addLibrary(.{
        .name = "DanzigGain",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-gain/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    danzig_gain.root_module.addImport("danzig", danzig_module);
    danzig_gain.root_module.linkLibrary(danzig_lib);

    // Install to zig-out/lib/
    b.installArtifact(danzig_gain);

    // Integration harness. Links the plugin itself so it can call the exported
    // GetPluginFactory entry point and drive it through the raw VST3 C ABI.
    const danzig_test = b.addExecutable(.{
        .name = "danzig_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-test/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    danzig_test.root_module.addImport("danzig", danzig_module);
    danzig_test.root_module.linkLibrary(danzig_lib);
    danzig_test.root_module.linkLibrary(danzig_gain);
    b.installArtifact(danzig_test);

    // Minimal plugin template. Built twice from one source: as the shared
    // library a host would load, and as an executable so the DSP can be run
    // and checked without a host.
    const danzig_minimal = b.addLibrary(.{
        .name = "DanzigMinimal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-minimal/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });
    danzig_minimal.root_module.addImport("danzig", danzig_module);
    danzig_minimal.root_module.linkLibrary(danzig_lib);
    b.installArtifact(danzig_minimal);

    const danzig_minimal_demo = b.addExecutable(.{
        .name = "danzig-minimal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-minimal/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    danzig_minimal_demo.root_module.addImport("danzig", danzig_module);
    danzig_minimal_demo.root_module.linkLibrary(danzig_lib);
    b.installArtifact(danzig_minimal_demo);

    const run_minimal = b.addRunArtifact(danzig_minimal_demo);
    const run_minimal_step = b.step("run-minimal", "Run the minimal plugin template offline");
    run_minimal_step.dependOn(&run_minimal.step);

    // Standalone audio processor
    const danzig_gain_standalone = b.addExecutable(.{
        .name = "danzig-gain-standalone",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-gain-standalone/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    danzig_gain_standalone.root_module.addImport("danzig", danzig_module);
    danzig_gain_standalone.root_module.linkLibrary(danzig_lib);
    b.installArtifact(danzig_gain_standalone);

    const run_standalone = b.addRunArtifact(danzig_gain_standalone);
    const run_standalone_step = b.step("run-standalone", "Run the standalone audio processor");
    run_standalone_step.dependOn(&run_standalone.step);

    // Web UI server
    const danzig_webui = b.addExecutable(.{
        .name = "danzig-webui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-webui/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    danzig_webui.root_module.addImport("danzig", danzig_module);
    danzig_webui.root_module.linkLibrary(danzig_lib);
    b.installArtifact(danzig_webui);

    // --- Universal VST3 bundle (macOS) ---------------------------------------
    //
    // A VST3 plugin ships as a bundle holding one universal binary, so hosts of
    // either architecture load the same file. Built per-arch and merged with
    // lipo. Kept behind the `vst3` step rather than the default install,
    // because it doubles compile work and only applies to macOS.
    if (target.result.os.tag == .macos) {
        addVst3Bundle(b, optimize, danzig_module);
    }

    // --- GUI example (macOS) -------------------------------------------------
    //
    // Needs the webview dependency, so it is only wired up when that has been
    // fetched. Links CoreAudio for device IO and WebKit via webview.
    // webview-zig's own build.zig.zon still carries a pre-0.16 hash format that
    // Zig 0.16 rejects, so the GUI example cannot be built there until upstream
    // updates. Everything else in danzig works on 0.16.
    const webview_supported = @import("builtin").zig_version.minor < 16;
    if (target.result.os.tag == .macos and webview_supported) {
        if (b.lazyDependency("webview", .{ .target = target, .optimize = optimize })) |webview_dep| {
            addGuiExample(b, target, optimize, danzig_module, danzig_lib, webview_dep);
        }
    }

    // Unit tests — pure Zig, no artifact or host required
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_unit_tests.step);

    // Integration tests — drives the built plugin through the raw VST3 C ABI
    const run_test = b.addRunArtifact(danzig_test);
    const integration_test_step = b.step("test-integration", "Run VST3 ABI integration tests only");
    integration_test_step.dependOn(&run_test.step);

    // Test step
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_test.step);
}

/// Build DanzigGain for both macOS architectures, merge them into one
/// universal binary, and lay out the .vst3 bundle around it.
fn addVst3Bundle(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    danzig_module: *std.Build.Module,
) void {
    const arches = [_]std.Target.Cpu.Arch{ .aarch64, .x86_64 };
    const suffixes = [_][]const u8{ "arm64", "x86" };

    const lipo = b.addSystemCommand(&.{ "lipo", "-create" });

    inline for (arches, suffixes) |arch, suffix| {
        const arch_target = b.resolveTargetQuery(.{ .cpu_arch = arch, .os_tag = .macos });

        const lib = b.addLibrary(.{
            .name = "danzig_" ++ suffix,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/root.zig"),
                .target = arch_target,
                .optimize = optimize,
            }),
            .linkage = .static,
        });

        const plugin = b.addLibrary(.{
            .name = "DanzigGain_" ++ suffix,
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/danzig-gain/root.zig"),
                .target = arch_target,
                .optimize = optimize,
            }),
            .linkage = .dynamic,
        });
        plugin.root_module.addImport("danzig", danzig_module);
        plugin.root_module.linkLibrary(lib);
        b.installArtifact(plugin);

        lipo.addArtifactArg(plugin);
    }

    lipo.addArg("-output");
    const universal = lipo.addOutputFileArg("DanzigGain");

    // VST3 bundles carry no file extension on the executable itself.
    const bundle = b.addWriteFiles();
    _ = bundle.add("Contents/Info.plist", infoPlist(b));
    _ = bundle.add("Contents/PkgInfo", "BNDL????");
    _ = bundle.addCopyFile(universal, "Contents/MacOS/DanzigGain");

    const install_bundle = b.addInstallDirectory(.{
        .source_dir = bundle.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "DanzigGain.vst3",
    });

    const vst3_step = b.step("vst3", "Build and package the universal VST3 bundle");
    vst3_step.dependOn(&install_bundle.step);

    // Hosts scan ~/Library/Audio/Plug-Ins/VST3 on macOS.
    const install_cmd = b.addSystemCommand(&.{ "sh", "-c", "rm -rf \"$HOME/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3\" && " ++
        "mkdir -p \"$HOME/Library/Audio/Plug-Ins/VST3\" && " ++
        "cp -R \"$1\" \"$HOME/Library/Audio/Plug-Ins/VST3/DanzigGain.vst3\"", "sh" });
    install_cmd.addDirectoryArg(bundle.getDirectory());

    const install_vst3_step = b.step("install-vst3", "Install the VST3 bundle to ~/Library/Audio/Plug-Ins/VST3/");
    install_vst3_step.dependOn(&install_cmd.step);
}

/// Standalone GUI host: a webview front end driving the gain processor over
/// CoreAudio.
fn addGuiExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    danzig_module: *std.Build.Module,
    danzig_lib: *std.Build.Step.Compile,
    webview_dep: *std.Build.Dependency,
) void {
    const coreaudio_module = b.addModule("coreaudio", .{
        .root_source_file = b.path("examples/danzig-gain-ui/coreaudio.zig"),
    });

    const gui = b.addExecutable(.{
        .name = "danzig-gain-ui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/danzig-gain-ui/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gui.root_module.addImport("danzig", danzig_module);
    gui.root_module.addImport("coreaudio", coreaudio_module);
    gui.root_module.addImport("webview", webview_dep.module("webview"));
    // The Zig bindings are declarations only; the implementation is webview's
    // C++ core, which the dependency exposes as a static library.
    gui.root_module.linkLibrary(webview_dep.artifact("webviewStatic"));
    // The UI is embedded rather than read at runtime, so the binary is
    // self-contained.
    gui.root_module.addAnonymousImport("ui_html", .{ .root_source_file = b.path("ui/index.html") });
    gui.root_module.linkLibrary(danzig_lib);
    gui.root_module.linkFramework("CoreAudio", .{});
    gui.root_module.linkFramework("CoreFoundation", .{});
    b.installArtifact(gui);

    const run_gui = b.addRunArtifact(gui);
    const run_gui_step = b.step("run-gui", "Run the standalone GUI app");
    run_gui_step.dependOn(&run_gui.step);
}

fn infoPlist(b: *std.Build) []const u8 {
    const template =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>CFBundleExecutable</key>
        \\    <string>DanzigGain</string>
        \\    <key>CFBundleIdentifier</key>
        \\    <string>com.danzig.DanzigGain</string>
        \\    <key>CFBundleName</key>
        \\    <string>DanzigGain</string>
        \\    <key>CFBundleDisplayName</key>
        \\    <string>Danzig Gain</string>
        \\    <key>CFBundlePackageType</key>
        \\    <string>BNDL</string>
        \\    <key>CFBundleSignature</key>
        \\    <string>????</string>
        \\    <key>CFBundleVersion</key>
        \\    <string>{s}</string>
        \\    <key>CFBundleShortVersionString</key>
        \\    <string>{s}</string>
        \\    <key>CFBundleInfoDictionaryVersion</key>
        \\    <string>6.0</string>
        \\    <key>CSResourcesFileMapped</key>
        \\    <true/>
        \\</dict>
        \\</plist>
        \\
    ;
    return b.fmt(template, .{ VERSION, VERSION });
}
