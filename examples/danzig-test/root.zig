// VST3 ABI integration harness.
//
// The unit tests in src/tests.zig cover the pure-Zig core. This binary covers
// the other half: it links the built DanzigGain plugin, calls the exported
// GetPluginFactory entry point, and drives the returned object through the raw
// VST3 C ABI the way a host would. Nothing here goes through Zig types that
// only exist inside the plugin, so a layout change that would break a real
// host breaks this too.
//
// The checks assert on content, not just on result codes. A factory that
// returns kResultOk and writes nothing is the failure mode this file exists to
// catch, so every buffer below is zeroed before the call and an untouched
// buffer is a failure.
//
// Run with `zig build test-integration`, or as part of `zig build test`.

const std = @import("std");
const danzig = @import("danzig");

// --- The C ABI, as a host sees it -----------------------------------------
//
// A VST3 object is a pointer whose first word is a pointer to a vtable of C
// function pointers. These declarations mirror Steinberg's headers. They are
// deliberately independent of the plugin's own definitions.

const kResultOk: i32 = 0;

const IUnknownVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.c) i32,
    addRef: *const fn (*anyopaque) callconv(.c) u32,
    release: *const fn (*anyopaque) callconv(.c) u32,
};

const IPluginFactoryVTable = extern struct {
    base: IUnknownVTable,
    getFactoryInfo: *const fn (*anyopaque, *PFactoryInfo) callconv(.c) i32,
    countClasses: *const fn (*anyopaque) callconv(.c) i32,
    getClassInfo: *const fn (*anyopaque, i32, *PClassInfo) callconv(.c) i32,
    createInstance: *const fn (*anyopaque, [*]const u8, [*]const u8, *?*anyopaque) callconv(.c) i32,
};

const PFactoryInfo = extern struct {
    vendor: [64]u8,
    url: [256]u8,
    email: [128]u8,
    flags: i32,
};

const PClassInfo = extern struct {
    cid: [16]u8,
    cardinality: i32,
    category: [32]u8,
    name: [64]u8,
};

const IComponentVTable = extern struct {
    base: IUnknownVTable,
    initialize: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    terminate: *const fn (*anyopaque) callconv(.c) i32,
    getControllerClassId: *const fn (*anyopaque, *[16]u8) callconv(.c) i32,
    setIoMode: *const fn (*anyopaque, i32) callconv(.c) i32,
    getBusCount: *const fn (*anyopaque, i32, i32) callconv(.c) i32,
    getBusInfo: *const fn (*anyopaque, i32, i32, i32, *BusInfo) callconv(.c) i32,
    getRoutingInfo: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) i32,
    activateBus: *const fn (*anyopaque, i32, i32, i32, u8) callconv(.c) i32,
    setActive: *const fn (*anyopaque, u8) callconv(.c) i32,
    setState: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    getState: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
};

const IAudioProcessorVTable = extern struct {
    base: IUnknownVTable,
    setBusArrangements: *const fn (*anyopaque, ?[*]u64, i32, ?[*]u64, i32) callconv(.c) i32,
    getBusArrangement: *const fn (*anyopaque, i32, i32, *u64) callconv(.c) i32,
    canProcessSampleSize: *const fn (*anyopaque, i32) callconv(.c) i32,
    getLatencySamples: *const fn (*anyopaque) callconv(.c) u32,
    setupProcessing: *const fn (*anyopaque, *ProcessSetup) callconv(.c) i32,
    setProcessing: *const fn (*anyopaque, u8) callconv(.c) i32,
    process: *const fn (*anyopaque, *ProcessData) callconv(.c) i32,
    getTailSamples: *const fn (*anyopaque) callconv(.c) u32,
};

const IEditControllerVTable = extern struct {
    base: IUnknownVTable,
    initialize: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    terminate: *const fn (*anyopaque) callconv(.c) i32,
    setComponentState: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    setState: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    getState: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    getParameterCount: *const fn (*anyopaque) callconv(.c) i32,
    getParameterInfo: *const fn (*anyopaque, i32, *ParameterInfo) callconv(.c) i32,
    getParamStringByValue: *const fn (*anyopaque, u32, f64, *[128]u16) callconv(.c) i32,
    getParamValueByString: *const fn (*anyopaque, u32, [*]const u16, *f64) callconv(.c) i32,
    normalizedParamToPlain: *const fn (*anyopaque, u32, f64) callconv(.c) f64,
    plainParamToNormalized: *const fn (*anyopaque, u32, f64) callconv(.c) f64,
    getParamNormalized: *const fn (*anyopaque, u32) callconv(.c) f64,
    setParamNormalized: *const fn (*anyopaque, u32, f64) callconv(.c) i32,
    setComponentHandler: *const fn (*anyopaque, ?*anyopaque) callconv(.c) i32,
    createView: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque,
};

const BusInfo = extern struct {
    mediaType: i32,
    direction: i32,
    channelCount: i32,
    name: [128]u16,
    busType: i32,
    flags: u32,
};

const ParameterInfo = extern struct {
    id: u32,
    title: [128]u16,
    shortTitle: [128]u16,
    units: [128]u16,
    stepCount: i32,
    defaultNormalizedValue: f64,
    unitId: i32,
    flags: i32,
};

const ProcessSetup = extern struct {
    processMode: i32,
    symbolicSampleSize: i32,
    maxSamplesPerBlock: i32,
    sampleRate: f64,
};

const AudioBusBuffers = extern struct {
    numChannels: i32,
    silenceFlags: u64,
    channelBuffers: ?[*][*]f32,
};

const ProcessData = extern struct {
    processMode: i32,
    symbolicSampleSize: i32,
    numSamples: i32,
    numInputs: i32,
    numOutputs: i32,
    inputs: ?[*]AudioBusBuffers,
    outputs: ?[*]AudioBusBuffers,
    inputParameterChanges: ?*anyopaque,
    outputParameterChanges: ?*anyopaque,
    inputEvents: ?*anyopaque,
    outputEvents: ?*anyopaque,
    processContext: ?*anyopaque,
};

const kAudio: i32 = 0;
const kInput: i32 = 0;
const kOutput: i32 = 1;
const kSample32: i32 = 0;

/// Any VST3 interface pointer, viewed as the host views it.
const FactoryObject = extern struct {
    vtbl: *const IPluginFactoryVTable,
};

const ComponentObject = extern struct {
    vtbl: *const IComponentVTable,
};

const ProcessorObject = extern struct {
    vtbl: *const IAudioProcessorVTable,
};

const ControllerObject = extern struct {
    vtbl: *const IEditControllerVTable,
};

/// Enough of a created object to reference-count it and query it.
const UnknownObject = extern struct {
    vtbl: *const IUnknownVTable,
};

// Interface ids, spelled out from the four words in DECLARE_CLASS_IID. On
// every platform except Windows they are stored big-endian in that order.
//
//   IComponent      0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802
//   IAudioProcessor 0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D
//   IEditController 0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E

const iid_component = [16]u8{
    0xE8, 0x31, 0xFF, 0x31, 0xF2, 0xD5, 0x43, 0x01,
    0x92, 0x8E, 0xBB, 0xEE, 0x25, 0x69, 0x78, 0x02,
};

const iid_audio_processor = [16]u8{
    0x42, 0x04, 0x3F, 0x99, 0xB7, 0xDA, 0x45, 0x3C,
    0xA5, 0x69, 0xE7, 0x9D, 0x9A, 0xAE, 0xC3, 0x3D,
};

const iid_edit_controller = [16]u8{
    0xDC, 0xD7, 0xBB, 0xE3, 0x77, 0x42, 0x44, 0x8D,
    0xA8, 0x74, 0xAA, 0xCC, 0x97, 0x9C, 0x75, 0x9E,
};

/// A class id no plugin should claim, and an IID no plugin should implement.
const cid_nonsense = [16]u8{
    0xBA, 0xDB, 0xAD, 0xBA, 0xDB, 0xAD, 0xBA, 0xDB,
    0xAD, 0xBA, 0xDB, 0xAD, 0xBA, 0xDB, 0xAD, 0xBA,
};

/// The category string a host filters on when looking for an effect.
const category_audio_effect = "Audio Module Class";

/// The module entry point every VST3 binary must export.
extern fn GetPluginFactory() ?*anyopaque;

/// macOS hosts load the bundle and call this before anything else. A missing
/// bundleEntry means the module is discarded no matter how good the factory
/// behind it is.
extern fn bundleEntry(bundle: ?*anyopaque) callconv(.c) bool;

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

/// Length of a NUL-terminated string inside a fixed-size C char array.
fn cLen(buf: []const u8) usize {
    return std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
}

fn cEquals(buf: []const u8, expected: []const u8) bool {
    return std.mem.eql(u8, buf[0..cLen(buf)], expected);
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |b| {
        if (b != 0) return false;
    }
    return true;
}

fn checkModuleEntry() void {
    std.debug.print("VST3 module entry\n", .{});
    check(bundleEntry(null), "bundleEntry accepts the load and reports success");
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

    // The factory implements no component interface, so a query for one must
    // fail rather than hand back a garbage pointer.
    var out: ?*anyopaque = @ptrFromInt(@as(usize, 0xdead));
    const qi = vtbl.base.queryInterface(raw.?, &iid_component, &out);
    check(qi != kResultOk, "factory queryInterface for an unsupported IID reports failure");
    check(out == null, "factory queryInterface nulls the out pointer on failure");

    // getFactoryInfo has to fill the struct, not merely return success.
    var finfo = std.mem.zeroes(PFactoryInfo);
    check(vtbl.getFactoryInfo(raw.?, &finfo) == kResultOk, "getFactoryInfo returns kResultOk");
    check(cLen(&finfo.vendor) > 0, "getFactoryInfo writes a vendor name");

    checkClassInfo(raw.?, vtbl);
}

fn checkClassInfo(raw: *anyopaque, vtbl: *const IPluginFactoryVTable) void {
    // Zeroed first, so anything still zero afterwards was never written.
    var info = std.mem.zeroes(PClassInfo);
    check(vtbl.getClassInfo(raw, 0, &info) == kResultOk, "getClassInfo(0) returns kResultOk");
    check(
        cEquals(&info.category, category_audio_effect),
        "getClassInfo(0) writes the \"Audio Module Class\" category",
    );
    check(cLen(&info.name) > 0, "getClassInfo(0) writes a non-empty class name");
    check(!allZero(&info.cid), "getClassInfo(0) writes a non-zero class id");
    check(info.cardinality != 0, "getClassInfo(0) writes a cardinality");

    // An index past the end is an error, not a silent success.
    var beyond = std.mem.zeroes(PClassInfo);
    check(vtbl.getClassInfo(raw, 1, &beyond) != kResultOk, "getClassInfo(1) reports an invalid index");

    checkCreateInstance(raw, vtbl, info.cid);
}

fn checkCreateInstance(raw: *anyopaque, vtbl: *const IPluginFactoryVTable, cid: [16]u8) void {
    // A class id the factory does not export must be refused outright.
    var rejected: ?*anyopaque = @ptrFromInt(@as(usize, 0xdead));
    const bad = vtbl.createInstance(raw, &cid_nonsense, &iid_component, &rejected);
    check(bad != kResultOk, "createInstance refuses an unknown class id");
    check(rejected == null, "createInstance nulls the out pointer for an unknown class id");

    // The class id getClassInfo advertised must produce a real object.
    var created: ?*anyopaque = null;
    const made = vtbl.createInstance(raw, &cid, &iid_component, &created);
    check(made == kResultOk, "createInstance accepts the advertised class id");
    check(created != null, "createInstance writes a non-null object");
    if (created == null) return;

    const object: *UnknownObject = @ptrCast(@alignCast(created.?));

    // The first word has to be a usable vtable pointer, which the calls below
    // exercise. An uninitialised struct would fault here.
    const added = object.vtbl.addRef(created.?);
    const released = object.vtbl.release(created.?);
    check(added == released + 1, "the created object counts references");

    checkObjectInterfaces(created.?, object);
    checkAudioPath(created.?);

    check(object.vtbl.release(created.?) == 0, "releasing the last reference drops the count to zero");
}

const block_frames = 64;

/// Run one block of DC through the plugin and return the last output sample.
/// DC makes the applied gain readable straight off the buffer.
fn renderDcBlock(processor: *ProcessorObject, raw: *anyopaque) ?f32 {
    var in_l = [_]f32{1.0} ** block_frames;
    var in_r = [_]f32{1.0} ** block_frames;
    var out_l = [_]f32{0.0} ** block_frames;
    var out_r = [_]f32{0.0} ** block_frames;

    var in_ptrs = [_][*]f32{ &in_l, &in_r };
    var out_ptrs = [_][*]f32{ &out_l, &out_r };

    var in_buses = [_]AudioBusBuffers{.{ .numChannels = 2, .silenceFlags = 0, .channelBuffers = &in_ptrs }};
    var out_buses = [_]AudioBusBuffers{.{ .numChannels = 2, .silenceFlags = 0, .channelBuffers = &out_ptrs }};

    var data = ProcessData{
        .processMode = 0,
        .symbolicSampleSize = kSample32,
        .numSamples = block_frames,
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &in_buses,
        .outputs = &out_buses,
        .inputParameterChanges = null,
        .outputParameterChanges = null,
        .inputEvents = null,
        .outputEvents = null,
        .processContext = null,
    };

    if (processor.vtbl.process(raw, &data) != kResultOk) return null;
    return out_l[block_frames - 1];
}

/// Drive the object the way a host does: initialize, describe the buses, set
/// processing up, run audio, and read the result back. A factory that hands
/// out a plausible-looking pointer still fails here if nothing behind it works.
fn checkAudioPath(created: *anyopaque) void {
    const component: *ComponentObject = @ptrCast(@alignCast(created));

    check(component.vtbl.initialize(created, null) == kResultOk, "IComponent.initialize accepts a host context");
    check(component.vtbl.getBusCount(created, kAudio, kInput) == 1, "the plugin reports one audio input bus");
    check(component.vtbl.getBusCount(created, kAudio, kOutput) == 1, "the plugin reports one audio output bus");

    var bus = std.mem.zeroes(BusInfo);
    const got_bus = component.vtbl.getBusInfo(created, kAudio, kOutput, 0, &bus);
    check(got_bus == kResultOk and bus.channelCount == 2, "the output bus reports two channels");
    check(bus.name[0] != 0, "getBusInfo writes a bus name");

    var processor_ptr: ?*anyopaque = null;
    _ = component.vtbl.base.queryInterface(created, &iid_audio_processor, &processor_ptr);
    var controller_ptr: ?*anyopaque = null;
    _ = component.vtbl.base.queryInterface(created, &iid_edit_controller, &controller_ptr);
    if (processor_ptr == null or controller_ptr == null) return;

    const processor: *ProcessorObject = @ptrCast(@alignCast(processor_ptr.?));
    const controller: *ControllerObject = @ptrCast(@alignCast(controller_ptr.?));
    defer _ = processor.vtbl.base.release(processor_ptr.?);
    defer _ = controller.vtbl.base.release(controller_ptr.?);

    checkParameters(controller, controller_ptr.?);

    check(
        processor.vtbl.canProcessSampleSize(processor_ptr.?, kSample32) == kResultOk,
        "the processor accepts 32-bit samples",
    );

    var setup = ProcessSetup{
        .processMode = 0,
        .symbolicSampleSize = kSample32,
        .maxSamplesPerBlock = block_frames,
        .sampleRate = 48000.0,
    };
    check(processor.vtbl.setupProcessing(processor_ptr.?, &setup) == kResultOk, "setupProcessing accepts 48 kHz");
    check(component.vtbl.setActive(created, 1) == kResultOk, "setActive(true) is accepted");
    check(processor.vtbl.setProcessing(processor_ptr.?, 1) == kResultOk, "setProcessing(true) is accepted");

    // The default gain is 0 dB, so a full-scale DC input comes out unchanged.
    const unity = renderDcBlock(processor, processor_ptr.?);
    check(unity != null, "process returns kResultOk");
    check(unity != null and @abs(unity.? - 1.0) < 1e-4, "the default 0 dB setting passes DC through at unity");

    // +6 dB is a factor of ~1.995. setProcessing is toggled so the smoother
    // starts the block already at the new target.
    _ = controller.vtbl.setParamNormalized(controller_ptr.?, 0, (6.0 + 48.0) / 96.0);
    _ = processor.vtbl.setProcessing(processor_ptr.?, 0);
    _ = processor.vtbl.setProcessing(processor_ptr.?, 1);
    const boosted = renderDcBlock(processor, processor_ptr.?);
    check(boosted != null and @abs(boosted.? - 1.99526) < 1e-3, "a +6 dB gain setting scales DC by ~1.995");

    // Bypass has to win over the gain setting.
    _ = controller.vtbl.setParamNormalized(controller_ptr.?, 1, 1.0);
    _ = processor.vtbl.setProcessing(processor_ptr.?, 0);
    _ = processor.vtbl.setProcessing(processor_ptr.?, 1);
    const bypassed = renderDcBlock(processor, processor_ptr.?);
    check(bypassed != null and bypassed.? == 1.0, "bypass passes the input through untouched");

    _ = processor.vtbl.setProcessing(processor_ptr.?, 0);
    _ = component.vtbl.setActive(created, 0);
    check(component.vtbl.terminate(created) == kResultOk, "terminate is accepted");
}

fn checkParameters(controller: *ControllerObject, raw: *anyopaque) void {
    check(controller.vtbl.getParameterCount(raw) == 2, "the controller exposes two parameters");

    var info = std.mem.zeroes(ParameterInfo);
    check(controller.vtbl.getParameterInfo(raw, 0, &info) == kResultOk, "getParameterInfo(0) returns kResultOk");
    check(info.title[0] != 0, "getParameterInfo(0) writes a parameter title");

    var bypass = std.mem.zeroes(ParameterInfo);
    check(controller.vtbl.getParameterInfo(raw, 1, &bypass) == kResultOk, "getParameterInfo(1) returns kResultOk");
    // kIsBypass is what tells a host which parameter its bypass button drives.
    check((bypass.flags & (1 << 16)) != 0, "the second parameter is flagged as the bypass");

    var beyond = std.mem.zeroes(ParameterInfo);
    check(controller.vtbl.getParameterInfo(raw, 2, &beyond) != kResultOk, "getParameterInfo(2) reports an invalid index");

    // A round trip through the display string is what a host does when a user
    // types a value into the generic editor.
    var text = std.mem.zeroes([128]u16);
    check(
        controller.vtbl.getParamStringByValue(raw, 0, 0.5, &text) == kResultOk and text[0] != 0,
        "getParamStringByValue writes a display string for the gain",
    );
    var parsed: f64 = -1.0;
    check(
        controller.vtbl.getParamValueByString(raw, 0, &text, &parsed) == kResultOk and @abs(parsed - 0.5) < 1e-6,
        "getParamValueByString parses its own display string back",
    );
}

fn checkObjectInterfaces(created: *anyopaque, object: *UnknownObject) void {
    // An audio effect must offer IAudioProcessor, otherwise a host has no way
    // to run it.
    var processor: ?*anyopaque = null;
    const qp = object.vtbl.queryInterface(created, &iid_audio_processor, &processor);
    check(qp == kResultOk and processor != null, "the object hands back IAudioProcessor");
    if (processor) |p| {
        const proc_obj: *UnknownObject = @ptrCast(@alignCast(p));
        _ = proc_obj.vtbl.release(p);
    }

    // This plugin keeps the controller on the same object, so the query must
    // succeed and must give a different interface pointer.
    var controller: ?*anyopaque = null;
    const qc = object.vtbl.queryInterface(created, &iid_edit_controller, &controller);
    check(qc == kResultOk and controller != null, "the object hands back IEditController");
    if (controller) |c| {
        check(c != created, "IEditController is a distinct interface pointer from IComponent");
        const ctrl_obj: *UnknownObject = @ptrCast(@alignCast(c));
        _ = ctrl_obj.vtbl.release(c);
    }

    // Anything unsupported must fail and leave the caller with null.
    var nothing: ?*anyopaque = @ptrFromInt(@as(usize, 0xdead));
    const qn = object.vtbl.queryInterface(created, &cid_nonsense, &nothing);
    check(qn != kResultOk, "the object refuses an unsupported IID");
    check(nothing == null, "the object nulls the out pointer for an unsupported IID");
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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("danzig integration harness\n\n", .{});

    checkModuleEntry();
    std.debug.print("\n", .{});
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
