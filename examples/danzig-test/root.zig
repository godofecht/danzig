// VST3 ABI integration harness.
//
// The unit tests in src/tests.zig cover the pure-Zig core. This binary covers
// the other half: it links the built DanzigGain plugin, calls the exported
// GetPluginFactory entry point, and drives the returned object through the raw
// VST3 C ABI the way a host would. Nothing here goes through Zig types that
// only exist inside the plugin, so a layout change that would break a real
// host breaks this too.
//
// Run with `zig build test-integration`, or as part of `zig build test`.

const std = @import("std");
const danzig = @import("danzig");

// --- The C ABI, as a host sees it -----------------------------------------
//
// A VST3 object is a pointer whose first word is a pointer to a vtable of C
// function pointers. These declarations mirror Steinberg's IPluginFactory
// layout. They are deliberately independent of the plugin's own definitions.

const IUnknownVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.c) i32,
    addRef: *const fn (*anyopaque) callconv(.c) u32,
    release: *const fn (*anyopaque) callconv(.c) u32,
};

const IPluginFactoryVTable = extern struct {
    base: IUnknownVTable,
    getFactoryInfo: *const fn (*anyopaque, *anyopaque) callconv(.c) i32,
    countClasses: *const fn (*anyopaque) callconv(.c) i32,
    getClassInfo: *const fn (*anyopaque, i32, *anyopaque) callconv(.c) i32,
    createInstance: *const fn (*anyopaque, [*]const u8, [*]const u8, *?*anyopaque) callconv(.c) i32,
};

/// Any VST3 interface pointer, viewed as the host views it.
const FactoryObject = extern struct {
    vtbl: *const IPluginFactoryVTable,
};

/// The module entry point every VST3 binary must export.
extern fn GetPluginFactory() ?*anyopaque;

// --- Harness ---------------------------------------------------------------

var failures: u32 = 0;

fn check(ok: bool, comptime label: []const u8) void {
    if (ok) {
        std.debug.print("  ok    {s}\n", .{label});
    } else {
        failures += 1;
        std.debug.print("  FAIL  {s}\n", .{label});
    }
}

fn checkFactoryAbi() void {
    std.debug.print("VST3 factory ABI\n", .{});

    const raw = GetPluginFactory();
    check(raw != null, "GetPluginFactory returns a non-null object");
    if (raw == null) return;

    const factory: *FactoryObject = @ptrCast(@alignCast(raw.?));
    const vtbl = factory.vtbl;

    // A host reads the first word of the object and calls through it. If the
    // plugin ever stops putting the vtable pointer first, this dereference is
    // where it shows up.
    check(vtbl.countClasses(raw.?) == 1, "countClasses reports one exported class");

    // Reference counting must be symmetric: a host addRefs before handing the
    // pointer around and releases when done.
    const after_add = vtbl.base.addRef(raw.?);
    const after_release = vtbl.base.release(raw.?);
    check(after_add == after_release + 1, "addRef/release move the count by exactly one");

    // The factory implements no other interface, so a query must fail rather
    // than hand back a garbage pointer.
    const iid = [_]u8{0} ** 16;
    var out: ?*anyopaque = @ptrFromInt(@as(usize, 0xdead));
    const qi = vtbl.base.queryInterface(raw.?, &iid, &out);
    check(qi != 0, "queryInterface for an unknown IID reports failure");

    var info: [512]u8 = undefined;
    check(vtbl.getFactoryInfo(raw.?, &info) == 0, "getFactoryInfo returns kResultOk");
    check(vtbl.getClassInfo(raw.?, 0, &info) == 0, "getClassInfo(0) returns kResultOk");
}

fn checkLibraryLinkage(allocator: std.mem.Allocator) void {
    std.debug.print("danzig static library\n", .{});

    var buf = danzig.AudioBuffer.init(allocator, 2, 64, 48000.0) catch {
        check(false, "AudioBuffer.init allocates");
        return;
    };
    defer buf.deinit(allocator);
    check(buf.channelCount == 2 and buf.sampleCount == 64, "AudioBuffer reports its geometry");

    // Unity gain must be bit-transparent through the same conversion the
    // plugin uses on the audio thread.
    check(@abs(danzig.dBToLinear(0.0) - 1.0) < 1e-6, "dBToLinear(0 dB) is unity");
    check(@abs(danzig.dBToLinear(6.0) - 1.99526) < 1e-4, "dBToLinear(+6 dB) is ~1.995");

    var store = danzig.ParamStore(4){};
    const gain = store.add(-48.0, 48.0, 0.5, 0.0, 48000.0);
    store.setNormalized(gain, 1.0);
    store.tickAll();
    check(@abs(store.getSmoothed(gain) - 48.0) < 1e-3, "ParamStore reaches +48 dB at full scale");
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("danzig integration harness\n\n", .{});

    checkFactoryAbi();
    std.debug.print("\n", .{});
    checkLibraryLinkage(allocator);

    std.debug.print("\n", .{});
    if (failures == 0) {
        std.debug.print("all integration checks passed\n", .{});
        return 0;
    }
    std.debug.print("{d} integration check(s) failed\n", .{failures});
    return 1;
}
