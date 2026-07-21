// Danzig Gain: a loadable VST3 gain plugin.
//
// This file is the whole plugin. It has three parts:
//
//   1. The DSP core (GainPlugin), which knows nothing about VST3.
//   2. One COM-style object exposing IComponent, IAudioProcessor and
//      IEditController over the same instance. VST3 usually splits processing
//      and editing into two classes; combining them is legal and is what the
//      SDK calls a single-component effect. It keeps the parameter store in
//      one place.
//   3. A static IPluginFactory, plus the module entry points a host looks for.
//
// The parameter store is lock-free, so the host thread can write a value while
// the audio thread is mid-block without either waiting on the other.

const std = @import("std");
const danzig = @import("danzig");
const vst3 = danzig.vst3;

// --- identity --------------------------------------------------------------

/// The class id the host stores in its project files. Changing it orphans
/// every session that already loaded this plugin.
const processor_cid = vst3.TUID{
    0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0,
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
};

const plugin_name = "Danzig Gain";
const vendor_name = "Superelectric";
const vendor_url = "https://superelectric.dev";
const vendor_email = "danzig@superelectric.dev";
const plugin_version = "0.1.0";
const sdk_version = "VST 3.7.0";

// --- parameters ------------------------------------------------------------

const num_params = 2;

/// Index into the ParamStore. Also the VST3 ParamID, which keeps the mapping
/// between the two trivial.
const ParamIndex = struct {
    pub const gain: u32 = 0;
    pub const bypass: u32 = 1;
};

const gain_min_db: f32 = -48.0;
const gain_max_db: f32 = 48.0;
const gain_default_norm: f32 = 0.5; // 0 dB
const gain_smoothing_ms: f32 = 20.0;

// --- 1. DSP core -----------------------------------------------------------

/// The audio half of the plugin. No allocation, no locks, no VST3 types.
pub const GainPlugin = struct {
    params: danzig.ParamStore(num_params) = .{},
    sample_rate: f32 = 48000.0,

    pub fn init(sample_rate: f32) GainPlugin {
        var self = GainPlugin{ .sample_rate = sample_rate };
        _ = self.params.add(gain_min_db, gain_max_db, gain_default_norm, gain_smoothing_ms, sample_rate);
        // Bypass is a switch, so smoothing it would produce a half-bypassed
        // state that means nothing.
        _ = self.params.add(0.0, 1.0, 0.0, 0.0, sample_rate);
        return self;
    }

    /// Re-derive the smoothing coefficient. It is a function of the sample
    /// rate, so a rate change invalidates it.
    pub fn setSampleRate(self: *GainPlugin, sample_rate: f32) void {
        self.sample_rate = sample_rate;
        self.params.params[ParamIndex.gain].setSmoothingMs(gain_smoothing_ms, sample_rate);
        self.params.snapAll();
    }

    pub fn isBypassed(self: *const GainPlugin) bool {
        return self.params.getNormalized(ParamIndex.bypass) >= 0.5;
    }

    /// One sample of gain. The smoother is advanced even when bypassed so that
    /// leaving bypass does not jump to a stale value.
    pub fn nextGain(self: *GainPlugin, bypassed: bool) f32 {
        const db = self.params.tick(ParamIndex.gain);
        return if (bypassed) 1.0 else danzig.dBToLinear(db);
    }
};

// --- 2. The VST3 object ----------------------------------------------------
//
// A host holds a pointer whose first word is a vtable pointer. This object
// carries three such one-word structs, one per interface it implements, and
// recovers itself from any of them with @fieldParentPtr. That is the plain
// version of what a C++ compiler does for multiple inheritance.

const ComponentIface = extern struct { vtbl: *const vst3.ComponentVTable };
const ProcessorIface = extern struct { vtbl: *const vst3.AudioProcessorVTable };
const ControllerIface = extern struct { vtbl: *const vst3.EditControllerVTable };

const allocator = std.heap.page_allocator;

const Component = struct {
    comp: ComponentIface = .{ .vtbl = &component_vtable },
    proc: ProcessorIface = .{ .vtbl = &processor_vtable },
    ctrl: ControllerIface = .{ .vtbl = &controller_vtable },

    ref_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    host_context: ?*anyopaque = null,
    handler: ?*vst3.ComponentHandler = null,
    initialized: bool = false,
    active: bool = false,
    processing: bool = false,

    setup: vst3.ProcessSetup = .{ .sampleRate = 44100.0, .maxSamplesPerBlock = 512 },
    input_arrangement: vst3.SpeakerArrangement = vst3.kStereo,
    output_arrangement: vst3.SpeakerArrangement = vst3.kStereo,

    dsp: GainPlugin = undefined,

    fn create() ?*Component {
        const self = allocator.create(Component) catch return null;
        self.* = .{};
        self.dsp = GainPlugin.init(44100.0);
        return self;
    }

    fn retain(self: *Component) u32 {
        return self.ref_count.fetchAdd(1, .monotonic) + 1;
    }

    fn discard(self: *Component) u32 {
        const previous = self.ref_count.fetchSub(1, .release);
        if (previous == 1) {
            _ = self.ref_count.load(.acquire);
            allocator.destroy(self);
            return 0;
        }
        return previous - 1;
    }
};

fn fromComponent(this: *anyopaque) *Component {
    const iface: *ComponentIface = @ptrCast(@alignCast(this));
    return @fieldParentPtr("comp", iface);
}

fn fromProcessor(this: *anyopaque) *Component {
    const iface: *ProcessorIface = @ptrCast(@alignCast(this));
    return @fieldParentPtr("proc", iface);
}

fn fromController(this: *anyopaque) *Component {
    const iface: *ControllerIface = @ptrCast(@alignCast(this));
    return @fieldParentPtr("ctrl", iface);
}

/// Shared by all three interfaces: they are one object, so one refcount and
/// one interface table.
fn componentQueryInterface(self: *Component, iid: *const vst3.TUID, obj: *?*anyopaque) vst3.TResult {
    const wanted = iid.*;

    // IPluginBase is inherited by both IComponent and IEditController. Handing
    // back the component is the convention.
    if (vst3.uidEqual(wanted, vst3.IID_FUnknown) or
        vst3.uidEqual(wanted, vst3.IID_IPluginBase) or
        vst3.uidEqual(wanted, vst3.IID_IComponent))
    {
        obj.* = @ptrCast(&self.comp);
    } else if (vst3.uidEqual(wanted, vst3.IID_IAudioProcessor)) {
        obj.* = @ptrCast(&self.proc);
    } else if (vst3.uidEqual(wanted, vst3.IID_IEditController)) {
        obj.* = @ptrCast(&self.ctrl);
    } else {
        obj.* = null;
        return vst3.kNoInterface;
    }

    _ = self.retain();
    return vst3.kResultOk;
}

// --- IComponent ------------------------------------------------------------

fn comp_queryInterface(this: *anyopaque, iid: *const vst3.TUID, obj: *?*anyopaque) callconv(.c) vst3.TResult {
    return componentQueryInterface(fromComponent(this), iid, obj);
}

fn comp_addRef(this: *anyopaque) callconv(.c) u32 {
    return fromComponent(this).retain();
}

fn comp_release(this: *anyopaque) callconv(.c) u32 {
    return fromComponent(this).discard();
}

fn comp_initialize(this: *anyopaque, context: ?*anyopaque) callconv(.c) vst3.TResult {
    const self = fromComponent(this);
    // A second initialize does nothing, so it must not claim success. Hosts
    // reach this path when they discover the controller by querying the
    // component and then initialize both handles.
    if (self.initialized) return vst3.kResultFalse;
    self.host_context = context;
    self.initialized = true;
    return vst3.kResultOk;
}

fn comp_terminate(this: *anyopaque) callconv(.c) vst3.TResult {
    const self = fromComponent(this);
    self.host_context = null;
    self.handler = null;
    self.initialized = false;
    return vst3.kResultOk;
}

fn comp_getControllerClassId(this: *anyopaque, class_id: *vst3.TUID) callconv(.c) vst3.TResult {
    _ = this;
    _ = class_id;
    // There is no separate controller class. kResultFalse tells the host to
    // look for IEditController on this object instead.
    return vst3.kResultFalse;
}

fn comp_setIoMode(this: *anyopaque, mode: vst3.IoMode) callconv(.c) vst3.TResult {
    _ = this;
    _ = mode;
    // The plugin behaves identically in every IO mode, so there is nothing to
    // store and nothing to honour.
    return vst3.kNotImplemented;
}

fn comp_getBusCount(this: *anyopaque, media: vst3.MediaType, dir: vst3.BusDirection) callconv(.c) i32 {
    _ = this;
    _ = dir;
    return if (media == vst3.kAudio) 1 else 0;
}

fn comp_getBusInfo(
    this: *anyopaque,
    media: vst3.MediaType,
    dir: vst3.BusDirection,
    index: i32,
    info: *vst3.BusInfo,
) callconv(.c) vst3.TResult {
    const self = fromComponent(this);
    if (media != vst3.kAudio or index != 0) return vst3.kInvalidArgument;
    if (dir != vst3.kInput and dir != vst3.kOutput) return vst3.kInvalidArgument;

    const arrangement = if (dir == vst3.kInput) self.input_arrangement else self.output_arrangement;

    info.* = .{
        .mediaType = vst3.kAudio,
        .direction = dir,
        .channelCount = @intCast(@popCount(arrangement)),
        .busType = vst3.kMain,
        .flags = vst3.kDefaultActive,
    };
    vst3.setUtf16(&info.name, if (dir == vst3.kInput) "Input" else "Output");
    return vst3.kResultOk;
}

fn comp_getRoutingInfo(this: *anyopaque, in: *vst3.RoutingInfo, out: *vst3.RoutingInfo) callconv(.c) vst3.TResult {
    _ = this;
    _ = in;
    _ = out;
    // One bus each way, so there is no routing to describe.
    return vst3.kNotImplemented;
}

fn comp_activateBus(
    this: *anyopaque,
    media: vst3.MediaType,
    dir: vst3.BusDirection,
    index: i32,
    state: u8,
) callconv(.c) vst3.TResult {
    _ = this;
    _ = state;
    if (media != vst3.kAudio or index != 0) return vst3.kInvalidArgument;
    if (dir != vst3.kInput and dir != vst3.kOutput) return vst3.kInvalidArgument;
    // Both buses are always live; there is no per-bus allocation to toggle.
    return vst3.kResultOk;
}

fn comp_setActive(this: *anyopaque, state: u8) callconv(.c) vst3.TResult {
    const self = fromComponent(this);
    self.active = state != 0;
    if (self.active) self.dsp.params.snapAll();
    return vst3.kResultOk;
}

fn comp_setState(this: *anyopaque, stream: ?*vst3.BStream) callconv(.c) vst3.TResult {
    const self = fromComponent(this);
    const s = stream orelse return vst3.kInvalidArgument;
    return if (readState(self, s)) vst3.kResultOk else vst3.kResultFalse;
}

fn comp_getState(this: *anyopaque, stream: ?*vst3.BStream) callconv(.c) vst3.TResult {
    const self = fromComponent(this);
    const s = stream orelse return vst3.kInvalidArgument;
    return if (writeState(self, s)) vst3.kResultOk else vst3.kInternalError;
}

const component_vtable: vst3.ComponentVTable = .{
    .base = .{
        .unknown = .{
            .queryInterface = comp_queryInterface,
            .addRef = comp_addRef,
            .release = comp_release,
        },
        .initialize = comp_initialize,
        .terminate = comp_terminate,
    },
    .getControllerClassId = comp_getControllerClassId,
    .setIoMode = comp_setIoMode,
    .getBusCount = comp_getBusCount,
    .getBusInfo = comp_getBusInfo,
    .getRoutingInfo = comp_getRoutingInfo,
    .activateBus = comp_activateBus,
    .setActive = comp_setActive,
    .setState = comp_setState,
    .getState = comp_getState,
};

// --- state -----------------------------------------------------------------
//
// Layout: "DZG1", a version word, a parameter count, then that many normalized
// values as little-endian doubles. The count is stored so a state written by a
// build with more parameters still loads the ones this build knows.

const state_magic = [4]u8{ 'D', 'Z', 'G', '1' };
const state_version: u32 = 1;
const state_size = 12 + num_params * 8;

fn writeState(self: *Component, stream: *vst3.BStream) bool {
    var buf: [state_size]u8 = undefined;
    @memcpy(buf[0..4], &state_magic);
    std.mem.writeInt(u32, buf[4..8], state_version, .little);
    std.mem.writeInt(u32, buf[8..12], num_params, .little);
    for (0..num_params) |i| {
        const value: f64 = self.dsp.params.getNormalized(@intCast(i));
        std.mem.writeInt(u64, buf[12 + i * 8 ..][0..8], @bitCast(value), .little);
    }
    return stream.write(&buf);
}

fn readState(self: *Component, stream: *vst3.BStream) bool {
    var buf: [state_size]u8 = undefined;
    const filled = stream.read(&buf).len;
    if (filled < 12) return false;
    if (!std.mem.eql(u8, buf[0..4], &state_magic)) return false;
    if (std.mem.readInt(u32, buf[4..8], .little) != state_version) return false;

    const stored = std.mem.readInt(u32, buf[8..12], .little);
    const available: u32 = @intCast((filled - 12) / 8);
    const n = @min(@min(stored, available), num_params);

    for (0..n) |i| {
        const bits = std.mem.readInt(u64, buf[12 + i * 8 ..][0..8], .little);
        const value: f64 = @bitCast(bits);
        self.dsp.params.setNormalized(@intCast(i), @floatCast(value));
    }
    return n > 0;
}

// --- IAudioProcessor -------------------------------------------------------

fn proc_queryInterface(this: *anyopaque, iid: *const vst3.TUID, obj: *?*anyopaque) callconv(.c) vst3.TResult {
    return componentQueryInterface(fromProcessor(this), iid, obj);
}

fn proc_addRef(this: *anyopaque) callconv(.c) u32 {
    return fromProcessor(this).retain();
}

fn proc_release(this: *anyopaque) callconv(.c) u32 {
    return fromProcessor(this).discard();
}

fn supportedArrangement(arrangement: vst3.SpeakerArrangement) bool {
    return arrangement == vst3.kMono or arrangement == vst3.kStereo;
}

fn proc_setBusArrangements(
    this: *anyopaque,
    inputs: ?[*]vst3.SpeakerArrangement,
    num_in: i32,
    outputs: ?[*]vst3.SpeakerArrangement,
    num_out: i32,
) callconv(.c) vst3.TResult {
    const self = fromProcessor(this);
    if (num_in != 1 or num_out != 1) return vst3.kResultFalse;

    const in_arr = (inputs orelse return vst3.kInvalidArgument)[0];
    const out_arr = (outputs orelse return vst3.kInvalidArgument)[0];

    // Gain is channel-independent, so any matched mono or stereo pair works.
    // Anything else is refused rather than accepted and ignored, which would
    // leave the host writing into channels that are never read.
    if (in_arr != out_arr) return vst3.kResultFalse;
    if (!supportedArrangement(out_arr)) return vst3.kResultFalse;

    self.input_arrangement = in_arr;
    self.output_arrangement = out_arr;
    return vst3.kResultTrue;
}

fn proc_getBusArrangement(
    this: *anyopaque,
    dir: vst3.BusDirection,
    index: i32,
    arrangement: *vst3.SpeakerArrangement,
) callconv(.c) vst3.TResult {
    const self = fromProcessor(this);
    if (index != 0) return vst3.kInvalidArgument;
    arrangement.* = switch (dir) {
        vst3.kInput => self.input_arrangement,
        vst3.kOutput => self.output_arrangement,
        else => return vst3.kInvalidArgument,
    };
    return vst3.kResultOk;
}

fn proc_canProcessSampleSize(this: *anyopaque, size: i32) callconv(.c) vst3.TResult {
    _ = this;
    // 64-bit processing is not implemented, so it is refused outright.
    return if (size == vst3.kSample32) vst3.kResultTrue else vst3.kResultFalse;
}

fn proc_getLatencySamples(this: *anyopaque) callconv(.c) u32 {
    _ = this;
    return 0;
}

fn proc_setupProcessing(this: *anyopaque, setup: *vst3.ProcessSetup) callconv(.c) vst3.TResult {
    const self = fromProcessor(this);
    if (setup.symbolicSampleSize != vst3.kSample32) return vst3.kResultFalse;
    if (setup.sampleRate <= 0.0) return vst3.kInvalidArgument;

    self.setup = setup.*;
    self.dsp.setSampleRate(@floatCast(setup.sampleRate));
    return vst3.kResultOk;
}

fn proc_setProcessing(this: *anyopaque, state: u8) callconv(.c) vst3.TResult {
    const self = fromProcessor(this);
    self.processing = state != 0;
    // Starting a run from a stale smoother would ramp audibly from wherever
    // the last run stopped.
    if (self.processing) self.dsp.params.snapAll();
    return vst3.kResultOk;
}

fn proc_getTailSamples(this: *anyopaque) callconv(.c) u32 {
    _ = this;
    return 0;
}

/// Apply queued automation before the block runs. Only the final point of each
/// queue is used, so a parameter moves once per block and the smoother turns
/// that into a per-sample ramp.
fn applyParameterChanges(self: *Component, data: *vst3.ProcessData) void {
    const changes = data.inputParameterChanges orelse return;
    const queues = changes.count();
    var q: i32 = 0;
    while (q < queues) : (q += 1) {
        const queue = changes.queue(q) orelse continue;
        const points = queue.pointCount();
        if (points <= 0) continue;
        const value = queue.pointValue(points - 1) orelse continue;
        const id = queue.parameterId();
        if (id >= num_params) continue;
        self.dsp.params.setNormalized(id, @floatCast(value));
    }
}

fn proc_process(this: *anyopaque, data: *vst3.ProcessData) callconv(.c) vst3.TResult {
    const self = fromProcessor(this);

    applyParameterChanges(self, data);

    // A block of zero samples is a parameter flush. The changes above are the
    // whole job.
    if (data.numSamples <= 0) return vst3.kResultOk;
    if (data.symbolicSampleSize != vst3.kSample32) return vst3.kResultFalse;
    if (data.numOutputs < 1) return vst3.kResultOk;

    const out_buses = data.outputs orelse return vst3.kInvalidArgument;
    const out_bus = &out_buses[0];
    const out_channels = out_bus.channelBuffers orelse return vst3.kInvalidArgument;
    const num_out: usize = @intCast(@max(out_bus.numChannels, 0));
    const frames: usize = @intCast(data.numSamples);

    // The input bus may be absent when the host runs the plugin with nothing
    // patched in, in which case there is nothing to scale.
    var in_channels: ?[*][*]vst3.Sample32 = null;
    var num_in: usize = 0;
    if (data.numInputs >= 1) {
        if (data.inputs) |in_buses| {
            const in_bus = &in_buses[0];
            if (in_bus.channelBuffers) |buffers| {
                in_channels = buffers;
                num_in = @intCast(@max(in_bus.numChannels, 0));
            }
        }
    }

    const bypassed = self.dsp.isBypassed();

    var frame: usize = 0;
    while (frame < frames) : (frame += 1) {
        const gain = self.dsp.nextGain(bypassed);
        var ch: usize = 0;
        while (ch < num_out) : (ch += 1) {
            const dst = out_channels[ch];
            if (ch < num_in) {
                dst[frame] = in_channels.?[ch][frame] * gain;
            } else {
                dst[frame] = 0.0;
            }
        }
    }

    // Claiming silence wrongly makes hosts skip downstream work, and this
    // plugin has no way to know the output is silent without scanning it.
    out_bus.silenceFlags = 0;
    return vst3.kResultOk;
}

const processor_vtable: vst3.AudioProcessorVTable = .{
    .unknown = .{
        .queryInterface = proc_queryInterface,
        .addRef = proc_addRef,
        .release = proc_release,
    },
    .setBusArrangements = proc_setBusArrangements,
    .getBusArrangement = proc_getBusArrangement,
    .canProcessSampleSize = proc_canProcessSampleSize,
    .getLatencySamples = proc_getLatencySamples,
    .setupProcessing = proc_setupProcessing,
    .setProcessing = proc_setProcessing,
    .process = proc_process,
    .getTailSamples = proc_getTailSamples,
};

// --- IEditController -------------------------------------------------------

fn ctrl_queryInterface(this: *anyopaque, iid: *const vst3.TUID, obj: *?*anyopaque) callconv(.c) vst3.TResult {
    return componentQueryInterface(fromController(this), iid, obj);
}

fn ctrl_addRef(this: *anyopaque) callconv(.c) u32 {
    return fromController(this).retain();
}

fn ctrl_release(this: *anyopaque) callconv(.c) u32 {
    return fromController(this).discard();
}

fn ctrl_initialize(this: *anyopaque, context: ?*anyopaque) callconv(.c) vst3.TResult {
    return comp_initialize(@ptrCast(&fromController(this).comp), context);
}

fn ctrl_terminate(this: *anyopaque) callconv(.c) vst3.TResult {
    return comp_terminate(@ptrCast(&fromController(this).comp));
}

fn ctrl_setComponentState(this: *anyopaque, stream: ?*vst3.BStream) callconv(.c) vst3.TResult {
    const self = fromController(this);
    const s = stream orelse return vst3.kInvalidArgument;
    // Processor and controller are the same object, so the component state is
    // already the controller state.
    return if (readState(self, s)) vst3.kResultOk else vst3.kResultFalse;
}

fn ctrl_setState(this: *anyopaque, stream: ?*vst3.BStream) callconv(.c) vst3.TResult {
    return comp_setState(@ptrCast(&fromController(this).comp), stream);
}

fn ctrl_getState(this: *anyopaque, stream: ?*vst3.BStream) callconv(.c) vst3.TResult {
    return comp_getState(@ptrCast(&fromController(this).comp), stream);
}

fn ctrl_getParameterCount(this: *anyopaque) callconv(.c) i32 {
    _ = this;
    return num_params;
}

fn ctrl_getParameterInfo(this: *anyopaque, index: i32, info: *vst3.ParameterInfo) callconv(.c) vst3.TResult {
    _ = this;
    if (index < 0 or index >= num_params) return vst3.kInvalidArgument;

    info.* = .{};
    switch (@as(u32, @intCast(index))) {
        ParamIndex.gain => {
            info.id = ParamIndex.gain;
            vst3.setUtf16(&info.title, "Gain");
            vst3.setUtf16(&info.shortTitle, "Gain");
            vst3.setUtf16(&info.units, "dB");
            info.stepCount = 0;
            info.defaultNormalizedValue = gain_default_norm;
            info.flags = vst3.kCanAutomate;
        },
        ParamIndex.bypass => {
            info.id = ParamIndex.bypass;
            vst3.setUtf16(&info.title, "Bypass");
            vst3.setUtf16(&info.shortTitle, "Byps");
            info.stepCount = 1;
            info.defaultNormalizedValue = 0.0;
            info.flags = vst3.kCanAutomate | vst3.kIsBypass;
        },
        else => return vst3.kInvalidArgument,
    }
    return vst3.kResultOk;
}

fn plainGainDb(normalized: vst3.ParamValue) f64 {
    const clamped = std.math.clamp(normalized, 0.0, 1.0);
    return gain_min_db + clamped * (gain_max_db - gain_min_db);
}

fn ctrl_getParamStringByValue(
    this: *anyopaque,
    id: vst3.ParamID,
    value: vst3.ParamValue,
    out: *[128]u16,
) callconv(.c) vst3.TResult {
    _ = this;
    var buf: [64]u8 = undefined;
    const text = switch (id) {
        ParamIndex.gain => std.fmt.bufPrint(&buf, "{d:.2}", .{plainGainDb(value)}) catch return vst3.kInternalError,
        ParamIndex.bypass => if (value >= 0.5) "On" else "Off",
        else => return vst3.kInvalidArgument,
    };
    vst3.setUtf16(out, text);
    return vst3.kResultOk;
}

fn ctrl_getParamValueByString(
    this: *anyopaque,
    id: vst3.ParamID,
    string: [*]const u16,
    value: *vst3.ParamValue,
) callconv(.c) vst3.TResult {
    _ = this;

    var buf: [64]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len - 1 and string[len] != 0) : (len += 1) {
        const c = string[len];
        // Anything outside ASCII cannot be part of a number or of "On"/"Off".
        if (c > 127) return vst3.kResultFalse;
        buf[len] = @intCast(c);
    }
    const text = std.mem.trim(u8, buf[0..len], " \t");

    switch (id) {
        ParamIndex.gain => {
            const db = std.fmt.parseFloat(f64, text) catch return vst3.kResultFalse;
            value.* = std.math.clamp((db - gain_min_db) / (gain_max_db - gain_min_db), 0.0, 1.0);
        },
        ParamIndex.bypass => {
            if (std.ascii.eqlIgnoreCase(text, "on") or std.mem.eql(u8, text, "1")) {
                value.* = 1.0;
            } else if (std.ascii.eqlIgnoreCase(text, "off") or std.mem.eql(u8, text, "0")) {
                value.* = 0.0;
            } else return vst3.kResultFalse;
        },
        else => return vst3.kInvalidArgument,
    }
    return vst3.kResultOk;
}

fn ctrl_normalizedParamToPlain(this: *anyopaque, id: vst3.ParamID, value: vst3.ParamValue) callconv(.c) vst3.ParamValue {
    _ = this;
    return switch (id) {
        ParamIndex.gain => plainGainDb(value),
        ParamIndex.bypass => if (value >= 0.5) 1.0 else 0.0,
        else => 0.0,
    };
}

fn ctrl_plainParamToNormalized(this: *anyopaque, id: vst3.ParamID, plain: vst3.ParamValue) callconv(.c) vst3.ParamValue {
    _ = this;
    return switch (id) {
        ParamIndex.gain => std.math.clamp((plain - gain_min_db) / (gain_max_db - gain_min_db), 0.0, 1.0),
        ParamIndex.bypass => if (plain >= 0.5) 1.0 else 0.0,
        else => 0.0,
    };
}

fn ctrl_getParamNormalized(this: *anyopaque, id: vst3.ParamID) callconv(.c) vst3.ParamValue {
    const self = fromController(this);
    if (id >= num_params) return 0.0;
    return self.dsp.params.getNormalized(id);
}

fn ctrl_setParamNormalized(this: *anyopaque, id: vst3.ParamID, value: vst3.ParamValue) callconv(.c) vst3.TResult {
    const self = fromController(this);
    if (id >= num_params) return vst3.kInvalidArgument;
    self.dsp.params.setNormalized(id, @floatCast(value));
    return vst3.kResultOk;
}

fn ctrl_setComponentHandler(this: *anyopaque, handler: ?*vst3.ComponentHandler) callconv(.c) vst3.TResult {
    const self = fromController(this);
    self.handler = handler;
    return vst3.kResultOk;
}

fn ctrl_createView(this: *anyopaque, name: [*:0]const u8) callconv(.c) ?*anyopaque {
    _ = this;
    _ = name;
    // No editor. A null return is how a plugin says the host should draw the
    // generic one.
    return null;
}

const controller_vtable: vst3.EditControllerVTable = .{
    .base = .{
        .unknown = .{
            .queryInterface = ctrl_queryInterface,
            .addRef = ctrl_addRef,
            .release = ctrl_release,
        },
        .initialize = ctrl_initialize,
        .terminate = ctrl_terminate,
    },
    .setComponentState = ctrl_setComponentState,
    .setState = ctrl_setState,
    .getState = ctrl_getState,
    .getParameterCount = ctrl_getParameterCount,
    .getParameterInfo = ctrl_getParameterInfo,
    .getParamStringByValue = ctrl_getParamStringByValue,
    .getParamValueByString = ctrl_getParamValueByString,
    .normalizedParamToPlain = ctrl_normalizedParamToPlain,
    .plainParamToNormalized = ctrl_plainParamToNormalized,
    .getParamNormalized = ctrl_getParamNormalized,
    .setParamNormalized = ctrl_setParamNormalized,
    .setComponentHandler = ctrl_setComponentHandler,
    .createView = ctrl_createView,
};

// --- 3. The factory --------------------------------------------------------
//
// One static object for the whole module. It implements IPluginFactory2 as
// well, which is how a host learns the sub-category and vendor strings.

const FactoryIface = extern struct { vtbl: *const vst3.PluginFactory2VTable };

var factory_ref_count = std.atomic.Value(u32).init(0);
var factory = FactoryIface{ .vtbl = &factory_vtable };

fn factory_queryInterface(this: *anyopaque, iid: *const vst3.TUID, obj: *?*anyopaque) callconv(.c) vst3.TResult {
    const wanted = iid.*;
    if (vst3.uidEqual(wanted, vst3.IID_FUnknown) or
        vst3.uidEqual(wanted, vst3.IID_IPluginFactory) or
        vst3.uidEqual(wanted, vst3.IID_IPluginFactory2))
    {
        obj.* = this;
        _ = factory_ref_count.fetchAdd(1, .monotonic);
        return vst3.kResultOk;
    }
    obj.* = null;
    return vst3.kNoInterface;
}

fn factory_addRef(this: *anyopaque) callconv(.c) u32 {
    _ = this;
    return factory_ref_count.fetchAdd(1, .monotonic) + 1;
}

fn factory_release(this: *anyopaque) callconv(.c) u32 {
    _ = this;
    // The factory is static, so the count is bookkeeping only and reaching
    // zero frees nothing.
    if (factory_ref_count.load(.monotonic) == 0) return 0;
    return factory_ref_count.fetchSub(1, .monotonic) - 1;
}

fn factory_getFactoryInfo(this: *anyopaque, info: *vst3.PFactoryInfo) callconv(.c) vst3.TResult {
    _ = this;
    info.* = .{};
    vst3.setAscii(&info.vendor, vendor_name);
    vst3.setAscii(&info.url, vendor_url);
    vst3.setAscii(&info.email, vendor_email);
    info.flags = vst3.kFactoryNoFlags;
    return vst3.kResultOk;
}

fn factory_countClasses(this: *anyopaque) callconv(.c) i32 {
    _ = this;
    return 1;
}

fn factory_getClassInfo(this: *anyopaque, index: i32, info: *vst3.PClassInfo) callconv(.c) vst3.TResult {
    _ = this;
    if (index != 0) return vst3.kInvalidArgument;
    info.* = .{ .cid = processor_cid, .cardinality = vst3.kManyInstances };
    vst3.setAscii(&info.category, vst3.kCategoryAudioEffect);
    vst3.setAscii(&info.name, plugin_name);
    return vst3.kResultOk;
}

fn factory_getClassInfo2(this: *anyopaque, index: i32, info: *vst3.PClassInfo2) callconv(.c) vst3.TResult {
    _ = this;
    if (index != 0) return vst3.kInvalidArgument;
    info.* = .{ .cid = processor_cid, .cardinality = vst3.kManyInstances };
    vst3.setAscii(&info.category, vst3.kCategoryAudioEffect);
    vst3.setAscii(&info.name, plugin_name);
    vst3.setAscii(&info.subCategories, "Fx");
    vst3.setAscii(&info.vendor, vendor_name);
    vst3.setAscii(&info.version, plugin_version);
    vst3.setAscii(&info.sdkVersion, sdk_version);
    info.classFlags = 0;
    return vst3.kResultOk;
}

fn factory_createInstance(
    this: *anyopaque,
    cid: [*]const u8,
    iid: [*]const u8,
    obj: *?*anyopaque,
) callconv(.c) vst3.TResult {
    _ = this;
    obj.* = null;

    const requested_class: vst3.TUID = cid[0..16].*;
    if (!vst3.uidEqual(requested_class, processor_cid)) return vst3.kNoInterface;

    const instance = Component.create() orelse return vst3.kOutOfMemory;

    // The new object starts at one reference. queryInterface takes a second
    // for the caller, so dropping ours leaves exactly the one the host owns,
    // and frees the object outright if it asked for an interface this plugin
    // does not implement.
    const requested_iface: vst3.TUID = iid[0..16].*;
    const result = componentQueryInterface(instance, &requested_iface, obj);
    _ = instance.discard();
    return result;
}

const factory_vtable: vst3.PluginFactory2VTable = .{
    .factory = .{
        .unknown = .{
            .queryInterface = factory_queryInterface,
            .addRef = factory_addRef,
            .release = factory_release,
        },
        .getFactoryInfo = factory_getFactoryInfo,
        .countClasses = factory_countClasses,
        .getClassInfo = factory_getClassInfo,
        .createInstance = factory_createInstance,
    },
    .getClassInfo2 = factory_getClassInfo2,
};

// --- module entry points ---------------------------------------------------
//
// A macOS host loads the bundle with CFBundle and calls bundleEntry before it
// looks for anything else. Without that symbol the module is discarded and no
// amount of correct factory code is ever reached. Linux and Windows hosts call
// the equivalents below.

export fn GetPluginFactory() ?*anyopaque {
    _ = factory_ref_count.fetchAdd(1, .monotonic);
    return @ptrCast(&factory);
}

var module_ref_count: i32 = 0;

export fn bundleEntry(bundle: ?*anyopaque) callconv(.c) bool {
    _ = bundle;
    module_ref_count += 1;
    return true;
}

export fn bundleExit() callconv(.c) bool {
    if (module_ref_count > 0) module_ref_count -= 1;
    return true;
}

export fn ModuleEntry(handle: ?*anyopaque) callconv(.c) bool {
    return bundleEntry(handle);
}

export fn ModuleExit() callconv(.c) bool {
    return bundleExit();
}

export fn InitDll() callconv(.c) bool {
    return bundleEntry(null);
}

export fn ExitDll() callconv(.c) bool {
    return bundleExit();
}

pub fn main() !void {
    std.debug.print("Danzig Gain is a VST3 plugin library.\n", .{});
    std.debug.print("Build the bundle with `zig build vst3` and load it in a host.\n", .{});
}
