// VST3 C ABI Bindings
// Minimal VST3 interface definitions for plugin development

pub const CUID = [16]u8;

pub const kInfinite = 0x7FFFFFFF;

pub const IID = [16]u8;

pub const TResult = i32;
pub const kResultOk: TResult = 0;
pub const kResultTrue: TResult = 1;
pub const kResultFalse: TResult = 0;
pub const kResultInvalidArgument: TResult = 2;
pub const kNotImplemented: TResult = 3;

pub const BusDirection = i32;
pub const kInput: BusDirection = 0;
pub const kOutput: BusDirection = 1;

pub const BusType = i32;
pub const kMain: BusType = 0;
pub const kAux: BusType = 1;

pub const SampleRate = f64;
pub const Sample32 = f32;
pub const Sample64 = f64;

pub const AudioBusBuffers = extern struct {
    numChannels: u32,
    silenceFlags: u64,
    channelBuffers32: [*][*]Sample32 = null,
};

pub const ProcessData = extern struct {
    processMode: i32 = 0,
    symbolicSampleSize: i32 = 0,
    numSamples: i32 = 0,
    numInputs: u32 = 0,
    numOutputs: u32 = 0,
    inputs: [*]AudioBusBuffers = null,
    outputs: [*]AudioBusBuffers = null,
    inputParameterChanges: ?*anyopaque = null,
    outputParameterChanges: ?*anyopaque = null,
    inputEvents: ?*anyopaque = null,
    outputEvents: ?*anyopaque = null,
    processContext: ?*ProcessContext = null,
};

pub const ProcessContext = extern struct {
    state: u32 = 0,
    sampleRate: SampleRate = 0,
    projectTimeSamples: i64 = 0,
    systemTime: i64 = 0,
    continousTimeSamples: i64 = 0,
    tempo: f64 = 0,
    barPositionMusic: f64 = 0,
    cycleStartMusic: f64 = 0,
    cycleEndMusic: f64 = 0,
    timeSigNumerator: i32 = 0,
    timeSigDenominator: i32 = 0,
};

pub const IUnknown = extern struct {
    queryInterface: *const fn (?*IUnknown, *const IID, ?*[*]?*anyopaque) callconv(.C) TResult = undefined,
    addRef: *const fn (?*IUnknown) callconv(.C) u32 = undefined,
    release: *const fn (?*IUnknown) callconv(.C) u32 = undefined,
};

pub const IPluginBase = extern struct {
    unknown: IUnknown,
    initialize: *const fn (?*IPluginBase, ?*anyopaque) callconv(.C) TResult = undefined,
    terminate: *const fn (?*IPluginBase) callconv(.C) TResult = undefined,
};

pub const IComponent = extern struct {
    pluginBase: IPluginBase,
    getControllerClassId: *const fn (?*IComponent, ?*CUID) callconv(.C) TResult = undefined,
    setIoMode: *const fn (?*IComponent, i32) callconv(.C) TResult = undefined,
    getBusCount: *const fn (?*IComponent, BusDirection, u32) callconv(.C) u32 = undefined,
    getBusInfo: *const fn (?*IComponent, BusDirection, u32, ?*BusInfo) callconv(.C) TResult = undefined,
    getRoutingInfo: *const fn (?*IComponent, ?*RoutingInfo, ?*RoutingInfo) callconv(.C) TResult = undefined,
    activateBus: *const fn (?*IComponent, BusDirection, u32, u8) callconv(.C) TResult = undefined,
    setActive: *const fn (?*IComponent, u8) callconv(.C) TResult = undefined,
    setState: *const fn (?*IComponent, ?*anyopaque) callconv(.C) TResult = undefined,
    getState: *const fn (?*IComponent, ?*anyopaque) callconv(.C) TResult = undefined,
};

pub const BusInfo = extern struct {
    mediaType: i32 = 0,
    direction: BusDirection = 0,
    channelCount: i32 = 0,
    name: [128]u16 = undefined,
    busType: BusType = 0,
    flags: u32 = 0,
};

pub const RoutingInfo = extern struct {
    inputBusIndex: i32 = 0,
    outputBusIndex: i32 = 0,
};

pub const IAudioProcessor = extern struct {
    queryInterface: *const fn (?*IAudioProcessor, *const IID, ?*[*]?*anyopaque) callconv(.C) TResult = undefined,
    addRef: *const fn (?*IAudioProcessor) callconv(.C) u32 = undefined,
    release: *const fn (?*IAudioProcessor) callconv(.C) u32 = undefined,
    setBusArrangements: *const fn (?*IAudioProcessor, [*]i64, u32, [*]i64, u32) callconv(.C) TResult = undefined,
    getBusArrangement: *const fn (?*IAudioProcessor, i32, i32, [*]i64) callconv(.C) TResult = undefined,
    canProcessSampleSize: *const fn (?*IAudioProcessor, i32) callconv(.C) TResult = undefined,
    getLatencySamples: *const fn (?*IAudioProcessor) callconv(.C) u32 = undefined,
    setupProcessing: *const fn (?*IAudioProcessor, ?*ProcessSetup) callconv(.C) TResult = undefined,
    setProcessing: *const fn (?*IAudioProcessor, u8) callconv(.C) TResult = undefined,
    process: *const fn (?*IAudioProcessor, ?*ProcessData) callconv(.C) TResult = undefined,
    getTailSamples: *const fn (?*IAudioProcessor) callconv(.C) u32 = undefined,
};

pub const ProcessSetup = extern struct {
    processMode: i32 = 0,
    symbolicSampleSize: i32 = 0,
    maxSamplesPerBlock: i32 = 0,
    sampleRate: SampleRate = 0,
};

pub const IEditController = extern struct {
    pluginBase: IPluginBase,
    setComponentState: *const fn (?*IEditController, ?*anyopaque) callconv(.C) TResult = undefined,
    setState: *const fn (?*IEditController, ?*anyopaque) callconv(.C) TResult = undefined,
    getState: *const fn (?*IEditController, ?*anyopaque) callconv(.C) TResult = undefined,
    getParameterCount: *const fn (?*IEditController) callconv(.C) i32 = undefined,
    getParameterInfo: *const fn (?*IEditController, i32, ?*ParameterInfo) callconv(.C) TResult = undefined,
    getParamStringByValue: *const fn (?*IEditController, i32, f64, [*]u16) callconv(.C) TResult = undefined,
    getParamValueByString: *const fn (?*IEditController, i32, [*]const u16, [*]f64) callconv(.C) TResult = undefined,
    normalizedParamToPlain: *const fn (?*IEditController, i32, f64) callconv(.C) f64 = undefined,
    plainParamToNormalized: *const fn (?*IEditController, i32, f64) callconv(.C) f64 = undefined,
    getParamNormalized: *const fn (?*IEditController, i32) callconv(.C) f64 = undefined,
    setParamNormalized: *const fn (?*IEditController, i32, f64) callconv(.C) TResult = undefined,
    setComponentHandler: *const fn (?*IEditController, ?*anyopaque) callconv(.C) TResult = undefined,
    createView: *const fn (?*IEditController, [*:0]const u8) callconv(.C) ?*anyopaque = undefined,
};

pub const ParameterInfo = extern struct {
    id: u32 = 0,
    title: [128]u16 = undefined,
    shortTitle: [128]u16 = undefined,
    units: [128]u16 = undefined,
    stepCount: i32 = 0,
    defaultNormalizedValue: f64 = 0.5,
    unitId: i32 = 0,
    flags: i32 = 0,
};

pub const kCanAutomate: i32 = 1 << 0;
pub const kIsReadOnly: i32 = 1 << 1;
pub const kIsWrapAround: i32 = 1 << 2;
pub const kIsList: i32 = 1 << 3;
pub const kIsProgramChange: i32 = 1 << 4;
pub const kBypass: i32 = 1 << 5;

pub const kAudio = 0;
pub const kEvent = 1;

pub const MediaType = i32;
pub const kMediaTypeAudio: MediaType = 0;
pub const kMediaTypeEvent: MediaType = 1;

pub const SymbolicSampleSizes = i32;
pub const kSample32: SymbolicSampleSizes = 0;
pub const kSample64: SymbolicSampleSizes = 1;
