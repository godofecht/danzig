const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Danzig library (static)
    const danzig_lib = b.addStaticLibrary(.{
        .name = "danzig",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Danzig module for import by other targets
    const danzig_module = b.addModule("danzig", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Danzig gain VST3 plugin (shared, embeds danzig)
    const danzig_gain = b.addSharedLibrary(.{
        .name = "DanzigGain",
        .root_source_file = b.path("examples/danzig-gain/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    danzig_gain.linkLibrary(danzig_lib);
    
    // Install to zig-out/lib/
    b.installArtifact(danzig_gain);

    // Test executable
    const danzig_test = b.addExecutable(.{
        .name = "danzig_test",
        .root_source_file = b.path("examples/danzig-test/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    danzig_test.linkLibrary(danzig_lib);
    b.installArtifact(danzig_test);

    // Standalone audio processor
    const danzig_gain_standalone = b.addExecutable(.{
        .name = "danzig-gain-standalone",
        .root_source_file = b.path("examples/danzig-gain-standalone/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    danzig_gain_standalone.root_module.addImport("danzig", danzig_module);
    danzig_gain_standalone.linkLibrary(danzig_lib);
    b.installArtifact(danzig_gain_standalone);

    // Web UI server
    const danzig_webui = b.addExecutable(.{
        .name = "danzig-webui",
        .root_source_file = b.path("examples/danzig-webui/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    danzig_webui.root_module.addImport("danzig", danzig_module);
    danzig_webui.linkLibrary(danzig_lib);
    b.installArtifact(danzig_webui);

    // Test step
    const test_step = b.step("test", "Run tests");
    const run_test = b.addRunArtifact(danzig_test);
    test_step.dependOn(&run_test.step);
}

