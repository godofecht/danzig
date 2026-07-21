// VST3 C ABI bindings.
//
// A VST3 interface is a pointer to a struct whose first word points at a
// vtable of C function pointers. The host never sees a Zig type, so every
// layout here has to match Steinberg's headers byte for byte. The types are
// therefore split in two: a `*VTable` struct holding the function pointers in
// declaration order, and a one-field `extern struct` that is the object the
// host actually holds.
//
// Interface inheritance is flattened: an IComponent vtable starts with the
// three FUnknown slots, then the two IPluginBase slots, then its own.
//
// Result codes follow the non-Windows branch of funknown.h, which is what
// macOS and Linux builds use. COM_COMPATIBLE is only set on Windows, where
// these become HRESULTs instead.

const std = @import("std");

pub const TUID = [16]u8;
pub const CUID = TUID;
pub const IID = TUID;
pub const TResult = i32;

pub const kNoInterface: TResult = -1;
pub const kResultOk: TResult = 0;
pub const kResultTrue: TResult = 0;
pub const kResultFalse: TResult = 1;
pub const kInvalidArgument: TResult = 2;
pub const kNotImplemented: TResult = 3;
pub const kInternalError: TResult = 4;
pub const kNotInitialized: TResult = 5;
pub const kOutOfMemory: TResult = 6;

/// Kept under its old name so existing callers keep compiling.
pub const kResultInvalidArgument: TResult = kInvalidArgument;

/// Build a TUID from the four 32-bit words used by DECLARE_CLASS_IID.
///
/// Steinberg stores them big-endian on every platform except Windows, where
/// COM_COMPATIBLE reorders the first three words to match a Windows GUID.
pub fn uid(a: u32, b: u32, c: u32, d: u32) TUID {
    var out: TUID = undefined;
    std.mem.writeInt(u32, out[0..4], a, .big);
    std.mem.writeInt(u32, out[4..8], b, .big);
    std.mem.writeInt(u32, out[8..12], c, .big);
    std.mem.writeInt(u32, out[12..16], d, .big);
    return out;
}

pub fn uidEqual(a: TUID, b: TUID) bool {
    return std.mem.eql(u8, &a, &b);
}

// --- interface identifiers -------------------------------------------------

pub const IID_FUnknown = uid(0x00000000, 0x00000000, 0xC0000000, 0x00000046);
pub const IID_IPluginBase = uid(0x22888DDB, 0x156E45AE, 0x8358B348, 0x08190625);
pub const IID_IPluginFactory = uid(0x7A4D811C, 0x52114A1F, 0xAED9D2EE, 0x0B43BF9F);
pub const IID_IPluginFactory2 = uid(0x0007B650, 0xF24B4C0B, 0xA464EDB9, 0xF00B2ABB);
pub const IID_IPluginFactory3 = uid(0x4555A2AB, 0xC1234E57, 0x9B122910, 0x36878931);

pub const IID_IComponent = uid(0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802);
pub const IID_IAudioProcessor = uid(0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D);
pub const IID_IEditController = uid(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E);
pub const IID_IComponentHandler = uid(0x93A0BEA3, 0x0BD045DB, 0x8E890B0C, 0xC1E46AC6);
pub const IID_IConnectionPoint = uid(0x70A4156F, 0x6E6E4026, 0x989148BF, 0xAA60D8D1);
pub const IID_IUnitInfo = uid(0x3D4BD6B5, 0x913A4FD2, 0xA886E768, 0xA5EB92C1);
pub const IID_IMidiMapping = uid(0xDF0FF9F7, 0x49B74669, 0xB63AB732, 0x7ADBF5E5);
pub const IID_IBStream = uid(0xC3BF6EA2, 0x30994752, 0x9B6BF990, 0x1EE33E9B);
pub const IID_IParameterChanges = uid(0xA4779663, 0x0BB64A56, 0xB44384A8, 0x466FEB9D);
pub const IID_IParamValueQueue = uid(0x01263A18, 0xED074F6F, 0x98C9D356, 0x4686F9BA);

// --- class registry --------------------------------------------------------

pub const kCategoryAudioEffect = "Audio Module Class";
pub const kCategoryComponentController = "Component Controller Class";

pub const kManyInstances: i32 = 0x7FFFFFFF;
/// Old name for the same constant.
pub const kInfinite = kManyInstances;

pub const PFactoryInfo = extern struct {
    vendor: [64]u8 = [_]u8{0} ** 64,
    url: [256]u8 = [_]u8{0} ** 256,
    email: [128]u8 = [_]u8{0} ** 128,
    flags: i32 = 0,
};

pub const kFactoryNoFlags: i32 = 0;
pub const kClassesDiscardable: i32 = 1 << 0;
pub const kLicenseCheck: i32 = 1 << 1;
pub const kComponentNonDiscardable: i32 = 1 << 3;
pub const kFactoryUnicode: i32 = 1 << 4;

pub const PClassInfo = extern struct {
    cid: TUID = [_]u8{0} ** 16,
    cardinality: i32 = kManyInstances,
    category: [32]u8 = [_]u8{0} ** 32,
    name: [64]u8 = [_]u8{0} ** 64,
};

pub const PClassInfo2 = extern struct {
    cid: TUID = [_]u8{0} ** 16,
    cardinality: i32 = kManyInstances,
    category: [32]u8 = [_]u8{0} ** 32,
    name: [64]u8 = [_]u8{0} ** 64,
    classFlags: u32 = 0,
    subCategories: [128]u8 = [_]u8{0} ** 128,
    vendor: [64]u8 = [_]u8{0} ** 64,
    version: [64]u8 = [_]u8{0} ** 64,
    sdkVersion: [64]u8 = [_]u8{0} ** 64,
};

pub const PClassInfoW = extern struct {
    cid: TUID = [_]u8{0} ** 16,
    cardinality: i32 = kManyInstances,
    category: [32]u8 = [_]u8{0} ** 32,
    name: [64]u16 = [_]u16{0} ** 64,
    classFlags: u32 = 0,
    subCategories: [128]u8 = [_]u8{0} ** 128,
    vendor: [64]u16 = [_]u16{0} ** 64,
    version: [64]u16 = [_]u16{0} ** 64,
    sdkVersion: [64]u16 = [_]u16{0} ** 64,
};

// --- media, buses, speakers ------------------------------------------------

pub const MediaType = i32;
pub const kAudio: MediaType = 0;
pub const kEvent: MediaType = 1;
pub const kMediaTypeAudio: MediaType = kAudio;
pub const kMediaTypeEvent: MediaType = kEvent;

pub const BusDirection = i32;
pub const kInput: BusDirection = 0;
pub const kOutput: BusDirection = 1;

pub const BusType = i32;
pub const kMain: BusType = 0;
pub const kAux: BusType = 1;

pub const kDefaultActive: u32 = 1 << 0;

pub const SpeakerArrangement = u64;
pub const kEmptyArrangement: SpeakerArrangement = 0;
pub const kSpeakerL: SpeakerArrangement = 1 << 0;
pub const kSpeakerR: SpeakerArrangement = 1 << 1;
pub const kSpeakerM: SpeakerArrangement = 1 << 19;
pub const kMono: SpeakerArrangement = kSpeakerM;
pub const kStereo: SpeakerArrangement = kSpeakerL | kSpeakerR;

pub const BusInfo = extern struct {
    mediaType: MediaType = kAudio,
    direction: BusDirection = kInput,
    channelCount: i32 = 0,
    name: [128]u16 = [_]u16{0} ** 128,
    busType: BusType = kMain,
    flags: u32 = 0,
};

pub const RoutingInfo = extern struct {
    mediaType: MediaType = kAudio,
    busIndex: i32 = 0,
    channel: i32 = -1,
};

pub const IoMode = i32;
pub const kSimple: IoMode = 0;
pub const kAdvanced: IoMode = 1;
pub const kOfflineProcessing: IoMode = 2;

// --- processing ------------------------------------------------------------

pub const SampleRate = f64;
pub const Sample32 = f32;
pub const Sample64 = f64;
pub const ParamID = u32;
pub const ParamValue = f64;

pub const SymbolicSampleSizes = i32;
pub const kSample32: SymbolicSampleSizes = 0;
pub const kSample64: SymbolicSampleSizes = 1;

pub const ProcessModes = i32;
pub const kRealtime: ProcessModes = 0;
pub const kPrefetch: ProcessModes = 1;
pub const kOffline: ProcessModes = 2;

pub const ProcessSetup = extern struct {
    processMode: i32 = 0,
    symbolicSampleSize: i32 = kSample32,
    maxSamplesPerBlock: i32 = 0,
    sampleRate: SampleRate = 0,
};

pub const AudioBusBuffers = extern struct {
    numChannels: i32 = 0,
    silenceFlags: u64 = 0,
    /// Union of Sample32** and Sample64**; which one is live depends on
    /// ProcessData.symbolicSampleSize.
    channelBuffers: ?[*][*]Sample32 = null,
};

pub const ProcessContext = extern struct {
    state: u32 = 0,
    sampleRate: f64 = 0,
    projectTimeSamples: i64 = 0,
    systemTime: i64 = 0,
    continousTimeSamples: i64 = 0,
    projectTimeMusic: f64 = 0,
    barPositionMusic: f64 = 0,
    cycleStartMusic: f64 = 0,
    cycleEndMusic: f64 = 0,
    tempo: f64 = 0,
    timeSigNumerator: i32 = 0,
    timeSigDenominator: i32 = 0,
    chordKeyNote: u8 = 0,
    chordRootNote: u8 = 0,
    chordMask: i16 = 0,
    smpteOffsetSubframes: i32 = 0,
    framesPerSecond: u32 = 0,
    frameRateFlags: u32 = 0,
    samplesToNextClock: i32 = 0,
};

pub const ProcessData = extern struct {
    processMode: i32 = 0,
    symbolicSampleSize: i32 = kSample32,
    numSamples: i32 = 0,
    numInputs: i32 = 0,
    numOutputs: i32 = 0,
    inputs: ?[*]AudioBusBuffers = null,
    outputs: ?[*]AudioBusBuffers = null,
    inputParameterChanges: ?*ParameterChanges = null,
    outputParameterChanges: ?*ParameterChanges = null,
    inputEvents: ?*anyopaque = null,
    outputEvents: ?*anyopaque = null,
    processContext: ?*ProcessContext = null,
};

// --- parameters ------------------------------------------------------------

pub const ParameterInfo = extern struct {
    id: ParamID = 0,
    title: [128]u16 = [_]u16{0} ** 128,
    shortTitle: [128]u16 = [_]u16{0} ** 128,
    units: [128]u16 = [_]u16{0} ** 128,
    stepCount: i32 = 0,
    defaultNormalizedValue: ParamValue = 0.0,
    unitId: i32 = 0,
    flags: i32 = 0,
};

pub const kNoFlags: i32 = 0;
pub const kCanAutomate: i32 = 1 << 0;
pub const kIsReadOnly: i32 = 1 << 1;
pub const kIsWrapAround: i32 = 1 << 2;
pub const kIsList: i32 = 1 << 3;
pub const kIsHidden: i32 = 1 << 4;
pub const kIsProgramChange: i32 = 1 << 15;
pub const kIsBypass: i32 = 1 << 16;

pub const kReloadComponent: i32 = 1 << 0;
pub const kIoChanged: i32 = 1 << 1;
pub const kParamValuesChanged: i32 = 1 << 2;
pub const kLatencyChanged: i32 = 1 << 3;
pub const kParamTitlesChanged: i32 = 1 << 4;

// --- vtables ---------------------------------------------------------------
//
// `this` is typed *anyopaque throughout. Each implementation knows which of
// its embedded interface objects a given vtable belongs to and recovers the
// owner with @fieldParentPtr.

pub const FUnknownVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const TUID, *?*anyopaque) callconv(.c) TResult,
    addRef: *const fn (*anyopaque) callconv(.c) u32,
    release: *const fn (*anyopaque) callconv(.c) u32,
};

pub const PluginFactoryVTable = extern struct {
    unknown: FUnknownVTable,
    getFactoryInfo: *const fn (*anyopaque, *PFactoryInfo) callconv(.c) TResult,
    countClasses: *const fn (*anyopaque) callconv(.c) i32,
    getClassInfo: *const fn (*anyopaque, i32, *PClassInfo) callconv(.c) TResult,
    createInstance: *const fn (*anyopaque, [*]const u8, [*]const u8, *?*anyopaque) callconv(.c) TResult,
};

pub const PluginFactory2VTable = extern struct {
    factory: PluginFactoryVTable,
    getClassInfo2: *const fn (*anyopaque, i32, *PClassInfo2) callconv(.c) TResult,
};

pub const PluginBaseVTable = extern struct {
    unknown: FUnknownVTable,
    initialize: *const fn (*anyopaque, ?*anyopaque) callconv(.c) TResult,
    terminate: *const fn (*anyopaque) callconv(.c) TResult,
};

pub const ComponentVTable = extern struct {
    base: PluginBaseVTable,
    getControllerClassId: *const fn (*anyopaque, *TUID) callconv(.c) TResult,
    setIoMode: *const fn (*anyopaque, IoMode) callconv(.c) TResult,
    getBusCount: *const fn (*anyopaque, MediaType, BusDirection) callconv(.c) i32,
    getBusInfo: *const fn (*anyopaque, MediaType, BusDirection, i32, *BusInfo) callconv(.c) TResult,
    getRoutingInfo: *const fn (*anyopaque, *RoutingInfo, *RoutingInfo) callconv(.c) TResult,
    activateBus: *const fn (*anyopaque, MediaType, BusDirection, i32, u8) callconv(.c) TResult,
    setActive: *const fn (*anyopaque, u8) callconv(.c) TResult,
    setState: *const fn (*anyopaque, ?*BStream) callconv(.c) TResult,
    getState: *const fn (*anyopaque, ?*BStream) callconv(.c) TResult,
};

pub const AudioProcessorVTable = extern struct {
    unknown: FUnknownVTable,
    setBusArrangements: *const fn (*anyopaque, ?[*]SpeakerArrangement, i32, ?[*]SpeakerArrangement, i32) callconv(.c) TResult,
    getBusArrangement: *const fn (*anyopaque, BusDirection, i32, *SpeakerArrangement) callconv(.c) TResult,
    canProcessSampleSize: *const fn (*anyopaque, i32) callconv(.c) TResult,
    getLatencySamples: *const fn (*anyopaque) callconv(.c) u32,
    setupProcessing: *const fn (*anyopaque, *ProcessSetup) callconv(.c) TResult,
    setProcessing: *const fn (*anyopaque, u8) callconv(.c) TResult,
    process: *const fn (*anyopaque, *ProcessData) callconv(.c) TResult,
    getTailSamples: *const fn (*anyopaque) callconv(.c) u32,
};

pub const EditControllerVTable = extern struct {
    base: PluginBaseVTable,
    setComponentState: *const fn (*anyopaque, ?*BStream) callconv(.c) TResult,
    setState: *const fn (*anyopaque, ?*BStream) callconv(.c) TResult,
    getState: *const fn (*anyopaque, ?*BStream) callconv(.c) TResult,
    getParameterCount: *const fn (*anyopaque) callconv(.c) i32,
    getParameterInfo: *const fn (*anyopaque, i32, *ParameterInfo) callconv(.c) TResult,
    getParamStringByValue: *const fn (*anyopaque, ParamID, ParamValue, *[128]u16) callconv(.c) TResult,
    getParamValueByString: *const fn (*anyopaque, ParamID, [*]const u16, *ParamValue) callconv(.c) TResult,
    normalizedParamToPlain: *const fn (*anyopaque, ParamID, ParamValue) callconv(.c) ParamValue,
    plainParamToNormalized: *const fn (*anyopaque, ParamID, ParamValue) callconv(.c) ParamValue,
    getParamNormalized: *const fn (*anyopaque, ParamID) callconv(.c) ParamValue,
    setParamNormalized: *const fn (*anyopaque, ParamID, ParamValue) callconv(.c) TResult,
    setComponentHandler: *const fn (*anyopaque, ?*ComponentHandler) callconv(.c) TResult,
    createView: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque,
};

// --- host-side interfaces we call ------------------------------------------

pub const kSeekSet: i32 = 0;
pub const kSeekCurrent: i32 = 1;
pub const kSeekEnd: i32 = 2;

pub const BStreamVTable = extern struct {
    unknown: FUnknownVTable,
    read: *const fn (*anyopaque, *anyopaque, i32, ?*i32) callconv(.c) TResult,
    write: *const fn (*anyopaque, *anyopaque, i32, ?*i32) callconv(.c) TResult,
    seek: *const fn (*anyopaque, i64, i32, ?*i64) callconv(.c) TResult,
    tell: *const fn (*anyopaque, *i64) callconv(.c) TResult,
};

/// A host-provided byte stream. Only the vtable pointer is ours to read.
pub const BStream = extern struct {
    vtbl: *const BStreamVTable,

    pub fn write(self: *BStream, bytes: []const u8) bool {
        var written: i32 = 0;
        const buf: *anyopaque = @constCast(@ptrCast(bytes.ptr));
        const r = self.vtbl.write(self, buf, @intCast(bytes.len), &written);
        return r == kResultOk and written == @as(i32, @intCast(bytes.len));
    }

    /// Reads up to `buf.len` bytes. Returns the slice actually filled.
    pub fn read(self: *BStream, buf: []u8) []u8 {
        var total: usize = 0;
        while (total < buf.len) {
            var got: i32 = 0;
            const dest: *anyopaque = @ptrCast(buf[total..].ptr);
            const r = self.vtbl.read(self, dest, @intCast(buf.len - total), &got);
            if (r != kResultOk or got <= 0) break;
            total += @intCast(got);
        }
        return buf[0..total];
    }
};

pub const ParamValueQueueVTable = extern struct {
    unknown: FUnknownVTable,
    getParameterId: *const fn (*anyopaque) callconv(.c) ParamID,
    getPointCount: *const fn (*anyopaque) callconv(.c) i32,
    getPoint: *const fn (*anyopaque, i32, *i32, *ParamValue) callconv(.c) TResult,
    addPoint: *const fn (*anyopaque, i32, ParamValue, *i32) callconv(.c) TResult,
};

pub const ParamValueQueue = extern struct {
    vtbl: *const ParamValueQueueVTable,

    pub fn parameterId(self: *ParamValueQueue) ParamID {
        return self.vtbl.getParameterId(self);
    }

    pub fn pointCount(self: *ParamValueQueue) i32 {
        return self.vtbl.getPointCount(self);
    }

    pub fn pointValue(self: *ParamValueQueue, index: i32) ?ParamValue {
        var offset: i32 = 0;
        var value: ParamValue = 0;
        if (self.vtbl.getPoint(self, index, &offset, &value) != kResultOk) return null;
        return value;
    }
};

pub const ParameterChangesVTable = extern struct {
    unknown: FUnknownVTable,
    getParameterCount: *const fn (*anyopaque) callconv(.c) i32,
    getParameterData: *const fn (*anyopaque, i32) callconv(.c) ?*ParamValueQueue,
    addParameterData: *const fn (*anyopaque, *const ParamID, *i32) callconv(.c) ?*ParamValueQueue,
};

pub const ParameterChanges = extern struct {
    vtbl: *const ParameterChangesVTable,

    pub fn count(self: *ParameterChanges) i32 {
        return self.vtbl.getParameterCount(self);
    }

    pub fn queue(self: *ParameterChanges, index: i32) ?*ParamValueQueue {
        return self.vtbl.getParameterData(self, index);
    }
};

pub const ComponentHandlerVTable = extern struct {
    unknown: FUnknownVTable,
    beginEdit: *const fn (*anyopaque, ParamID) callconv(.c) TResult,
    performEdit: *const fn (*anyopaque, ParamID, ParamValue) callconv(.c) TResult,
    endEdit: *const fn (*anyopaque, ParamID) callconv(.c) TResult,
    restartComponent: *const fn (*anyopaque, i32) callconv(.c) TResult,
};

pub const ComponentHandler = extern struct {
    vtbl: *const ComponentHandlerVTable,

    pub fn restart(self: *ComponentHandler, flags: i32) void {
        _ = self.vtbl.restartComponent(self, flags);
    }
};

// --- string helpers --------------------------------------------------------

/// Copy an ASCII string into a NUL-padded fixed-size char array. The last byte
/// is always left as NUL so the host can read it as a C string.
pub fn setAscii(dest: []u8, src: []const u8) void {
    @memset(dest, 0);
    const n = @min(dest.len - 1, src.len);
    @memcpy(dest[0..n], src[0..n]);
}

/// Copy ASCII into a NUL-padded UTF-16 array, the String128 convention.
pub fn setUtf16(dest: []u16, src: []const u8) void {
    @memset(dest, 0);
    const n = @min(dest.len - 1, src.len);
    for (0..n) |i| dest[i] = src[i];
}

comptime {
    // These sizes are part of the ABI. If one drifts, a host reading the
    // struct reads the wrong fields and there is no error to catch it at
    // runtime.
    std.debug.assert(@sizeOf(PClassInfo) == 116);
    std.debug.assert(@sizeOf(PClassInfo2) == 440);
    std.debug.assert(@sizeOf(PFactoryInfo) == 452);
    std.debug.assert(@sizeOf(ParameterInfo) == 792);
    std.debug.assert(@sizeOf(AudioBusBuffers) == 24);
    std.debug.assert(@sizeOf(ProcessSetup) == 24);
    std.debug.assert(@offsetOf(ProcessData, "inputs") == 24);
}
