// CLAP 1.x C ABI. Field order and signatures follow free-audio/clap/include/clap.
pub const Version = extern struct {
    major: u32 = 1,
    minor: u32 = 2,
    revision: u32 = 0,
};

pub const Host = opaque {};

pub const Descriptor = extern struct {
    clap_version: Version,
    id: [*:0]const u8,
    name: [*:0]const u8,
    vendor: ?[*:0]const u8,
    url: ?[*:0]const u8,
    manual_url: ?[*:0]const u8,
    support_url: ?[*:0]const u8,
    version: ?[*:0]const u8,
    description: ?[*:0]const u8,
    features: [*]const ?[*:0]const u8,
};

pub const EventHeader = extern struct {
    size: u32,
    time: u32,
    space_id: u16,
    @"type": u16,
    flags: u32,
};

pub const EventParamValue = extern struct {
    header: EventHeader,
    param_id: u32,
    cookie: ?*anyopaque,
    note_id: i32,
    port_index: i16,
    channel: i16,
    key: i16,
    value: f64,
};

pub const InputEvents = extern struct {
    ctx: ?*anyopaque,
    size: *const fn (*const InputEvents) callconv(.c) u32,
    get: *const fn (*const InputEvents, u32) callconv(.c) ?*const EventHeader,
};

pub const OutputEvents = extern struct {
    ctx: ?*anyopaque,
    try_push: *const fn (*const OutputEvents, *const EventHeader) callconv(.c) bool,
};

pub const AudioBuffer = extern struct {
    data32: ?[*][*]f32,
    data64: ?[*][*]f64,
    channel_count: u32,
    latency: u32,
    constant_mask: u64,
};

pub const Process = extern struct {
    steady_time: i64,
    frames_count: u32,
    transport: ?*const anyopaque,
    audio_inputs: ?[*]const AudioBuffer,
    audio_outputs: ?[*]AudioBuffer,
    audio_inputs_count: u32,
    audio_outputs_count: u32,
    in_events: ?*const InputEvents,
    out_events: ?*const OutputEvents,
};

pub const Plugin = extern struct {
    desc: *const Descriptor,
    plugin_data: ?*anyopaque,
    init: *const fn (*const Plugin) callconv(.c) bool,
    destroy: *const fn (*const Plugin) callconv(.c) void,
    activate: *const fn (*const Plugin, f64, u32, u32) callconv(.c) bool,
    deactivate: *const fn (*const Plugin) callconv(.c) void,
    start_processing: *const fn (*const Plugin) callconv(.c) bool,
    stop_processing: *const fn (*const Plugin) callconv(.c) void,
    reset: *const fn (*const Plugin) callconv(.c) void,
    process: *const fn (*const Plugin, *const Process) callconv(.c) i32,
    get_extension: *const fn (*const Plugin, [*:0]const u8) callconv(.c) ?*const anyopaque,
    on_main_thread: *const fn (*const Plugin) callconv(.c) void,
};

pub const PluginFactory = extern struct {
    get_plugin_count: *const fn (*const PluginFactory) callconv(.c) u32,
    get_plugin_descriptor: *const fn (*const PluginFactory, u32) callconv(.c) ?*const Descriptor,
    create_plugin: *const fn (*const PluginFactory, *const Host, [*:0]const u8) callconv(.c) ?*const Plugin,
};

pub const Entry = extern struct {
    clap_version: Version,
    init: *const fn ([*:0]const u8) callconv(.c) bool,
    deinit: *const fn () callconv(.c) void,
    get_factory: *const fn ([*:0]const u8) callconv(.c) ?*const anyopaque,
};

pub const PortInfo = extern struct {
    id: u32,
    name: [256]u8,
    flags: u32,
    channel_count: u32,
    port_type: ?[*:0]const u8,
    in_place_pair: u32,
};

pub const AudioPorts = extern struct {
    count: *const fn (*const Plugin, bool) callconv(.c) u32,
    get: *const fn (*const Plugin, u32, bool, *PortInfo) callconv(.c) bool,
};

pub const ParamInfo = extern struct {
    id: u32,
    flags: u32,
    cookie: ?*anyopaque,
    name: [256]u8,
    module: [1024]u8,
    min_value: f64,
    max_value: f64,
    default_value: f64,
};

pub const Params = extern struct {
    count: *const fn (*const Plugin) callconv(.c) u32,
    get_info: *const fn (*const Plugin, u32, *ParamInfo) callconv(.c) bool,
    get_value: *const fn (*const Plugin, u32, *f64) callconv(.c) bool,
    value_to_text: *const fn (*const Plugin, u32, f64, [*]u8, u32) callconv(.c) bool,
    text_to_value: *const fn (*const Plugin, u32, [*:0]const u8, *f64) callconv(.c) bool,
    flush: *const fn (*const Plugin, *const InputEvents, *const OutputEvents) callconv(.c) void,
};

pub const InputStream = extern struct {
    ctx: ?*anyopaque,
    read: *const fn (*const InputStream, *anyopaque, u64) callconv(.c) i64,
};

pub const OutputStream = extern struct {
    ctx: ?*anyopaque,
    write: *const fn (*const OutputStream, *const anyopaque, u64) callconv(.c) i64,
};

pub const State = extern struct {
    save: *const fn (*const Plugin, *const OutputStream) callconv(.c) bool,
    load: *const fn (*const Plugin, *const InputStream) callconv(.c) bool,
};

pub const event_param_value: u16 = 5;
pub const process_error: i32 = 0;
pub const process_continue: i32 = 1;
pub const param_automatable: u32 = 1 << 5;
pub const param_stepped: u32 = 1 << 0;
pub const param_bypass: u32 = 1 << 4;
pub const audio_port_main: u32 = 1;
pub const invalid_id: u32 = 0xffffffff;

test "CLAP ABI structure sizes" {
    const std = @import("std");
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(Version));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(EventHeader));
    if (@sizeOf(usize) == 8) {
        try std.testing.expectEqual(@as(usize, 56), @sizeOf(EventParamValue));
        try std.testing.expectEqual(@as(usize, 40), @sizeOf(AudioBuffer));
        try std.testing.expectEqual(@as(usize, 104), @sizeOf(Plugin));
    }
}
