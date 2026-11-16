// Danzig Gain CLAP adapter. DSP and parameter storage are shared with the VST3 example.
const std = @import("std");
const clap = @import("danzig").clap;
const core = @import("../danzig-gain/dsp.zig");

const plugin_id = "dev.superelectric.danzig.gain";
const features = [_]?[*:0]const u8{ "audio-effect", "stereo", null };
const descriptor = clap.Descriptor{
    .clap_version = .{},
    .id = plugin_id,
    .name = "Danzig Gain",
    .vendor = "Superelectric",
    .url = "https://superelectric.dev",
    .manual_url = null,
    .support_url = null,
    .version = "0.1.0",
    .description = "Stereo gain with smoothed automation and bypass",
    .features = features[0..].ptr,
};

const Instance = struct {
    plugin: clap.Plugin,
    dsp: core.GainPlugin,
    active: bool = false,
    processing: bool = false,
};

fn instance(plugin: *const clap.Plugin) *Instance {
    return @ptrCast(@alignCast(plugin.plugin_data.?));
}

fn pluginInit(plugin: *const clap.Plugin) callconv(.c) bool {
    _ = plugin;
    return true;
}

fn pluginDestroy(plugin: *const clap.Plugin) callconv(.c) void {
    std.heap.page_allocator.destroy(instance(plugin));
}

fn pluginActivate(plugin: *const clap.Plugin, sample_rate: f64, min_frames: u32, max_frames: u32) callconv(.c) bool {
    if (!std.math.isFinite(sample_rate) or sample_rate <= 0 or max_frames == 0 or min_frames > max_frames) return false;
    const self = instance(plugin);
    self.dsp.setSampleRate(@floatCast(sample_rate));
    self.active = true;
    return true;
}

fn pluginDeactivate(plugin: *const clap.Plugin) callconv(.c) void {
    const self = instance(plugin);
    self.processing = false;
    self.active = false;
}

fn startProcessing(plugin: *const clap.Plugin) callconv(.c) bool {
    const self = instance(plugin);
    if (!self.active) return false;
    self.processing = true;
    return true;
}

fn stopProcessing(plugin: *const clap.Plugin) callconv(.c) void {
    instance(plugin).processing = false;
}

fn reset(plugin: *const clap.Plugin) callconv(.c) void {
    instance(plugin).dsp.params.snapAll();
}

fn plainValue(self: *const Instance, id: u32) ?f64 {
    if (id >= core.num_params) return null;
    const norm = self.dsp.params.getNormalized(id);
    return if (id == core.ParamIndex.gain)
        @as(f64, norm) * 96.0 - 48.0
    else if (norm >= 0.5) @as(f64, 1.0) else @as(f64, 0.0);
}

fn setPlain(self: *Instance, id: u32, value: f64) void {
    if (!std.math.isFinite(value)) return;
    switch (id) {
        core.ParamIndex.gain => self.dsp.params.setNormalized(id, @floatCast(std.math.clamp((value + 48.0) / 96.0, 0.0, 1.0))),
        core.ParamIndex.bypass => self.dsp.params.setNormalized(id, if (value >= 0.5) 1.0 else 0.0),
        else => {},
    }
}

fn applyEvent(self: *Instance, header: *const clap.EventHeader) void {
    if (header.space_id != 0 or header.@"type" != clap.event_param_value or header.size < @sizeOf(clap.EventParamValue)) return;
    const event: *const clap.EventParamValue = @ptrCast(@alignCast(header));
    // Per-note modulation is deliberately not advertised by this effect.
    if (event.note_id != -1 or event.port_index != -1 or event.channel != -1 or event.key != -1) return;
    setPlain(self, event.param_id, event.value);
}

fn flushEvents(self: *Instance, events: ?*const clap.InputEvents) void {
    const list = events orelse return;
    for (0..list.size(list)) |i| {
        if (list.get(list, @intCast(i))) |header| applyEvent(self, header);
    }
}

fn processAudio(plugin: *const clap.Plugin, process: *const clap.Process) callconv(.c) i32 {
    const self = instance(plugin);
    if (!self.processing or process.audio_outputs_count != 1 or process.audio_inputs_count != 1) return clap.process_error;
    const inputs = process.audio_inputs orelse return clap.process_error;
    const outputs = process.audio_outputs orelse return clap.process_error;
    const input = &inputs[0];
    const output = &outputs[0];
    const in_data = input.data32 orelse return clap.process_error;
    const out_data = output.data32 orelse return clap.process_error;
    if (input.channel_count != 2 or output.channel_count != 2) return clap.process_error;

    const events = process.in_events;
    const count: u32 = if (events) |list| list.size(list) else 0;
    var next: u32 = 0;
    var frame: u32 = 0;
    while (frame < process.frames_count) : (frame += 1) {
        while (next < count) {
            const header = events.?.get(events.?, next) orelse {
                next += 1;
                continue;
            };
            if (header.time > frame) break;
            applyEvent(self, header);
            next += 1;
        }
        const gain = self.dsp.nextGain(self.dsp.isBypassed());
        for (0..2) |channel| {
            const constant = (input.constant_mask & (@as(u64, 1) << @intCast(channel))) != 0;
            const source_frame: usize = if (constant) 0 else frame;
            out_data[channel][frame] = in_data[channel][source_frame] * gain;
        }
    }
    // Zero-frame process() is allowed to carry automation.
    while (next < count) : (next += 1) {
        if (events.?.get(events.?, next)) |header| applyEvent(self, header);
    }
    output.constant_mask = 0;
    return clap.process_continue;
}

fn getExtension(_: *const clap.Plugin, id: [*:0]const u8) callconv(.c) ?*const anyopaque {
    const name = std.mem.span(id);
    if (std.mem.eql(u8, name, "clap.audio-ports")) return @ptrCast(&audio_ports);
    if (std.mem.eql(u8, name, "clap.params")) return @ptrCast(&params);
    if (std.mem.eql(u8, name, "clap.state")) return @ptrCast(&state);
    return null;
}

fn onMainThread(_: *const clap.Plugin) callconv(.c) void {}

fn portCount(_: *const clap.Plugin, _: bool) callconv(.c) u32 {
    return 1;
}

fn getPort(_: *const clap.Plugin, index: u32, is_input: bool, info: *clap.PortInfo) callconv(.c) bool {
    if (index != 0) return false;
    info.* = std.mem.zeroes(clap.PortInfo);
    info.id = 0;
    info.flags = clap.audio_port_main;
    info.channel_count = 2;
    info.port_type = "stereo";
    info.in_place_pair = 0;
    const name = if (is_input) "Stereo In" else "Stereo Out";
    @memcpy(info.name[0..name.len], name);
    return true;
}

const audio_ports = clap.AudioPorts{ .count = portCount, .get = getPort };

fn paramCount(_: *const clap.Plugin) callconv(.c) u32 {
    return core.num_params;
}

fn paramInfo(_: *const clap.Plugin, index: u32, info: *clap.ParamInfo) callconv(.c) bool {
    if (index >= core.num_params) return false;
    info.* = std.mem.zeroes(clap.ParamInfo);
    info.id = index;
    info.flags = clap.param_automatable;
    if (index == core.ParamIndex.gain) {
        @memcpy(info.name[0..4], "Gain");
        info.min_value = -48.0;
        info.max_value = 48.0;
        info.default_value = 0.0;
    } else {
        @memcpy(info.name[0..6], "Bypass");
        info.flags |= clap.param_stepped | clap.param_bypass;
        info.min_value = 0.0;
        info.max_value = 1.0;
        info.default_value = 0.0;
    }
    return true;
}

fn paramGetValue(plugin: *const clap.Plugin, id: u32, out: *f64) callconv(.c) bool {
    out.* = plainValue(instance(plugin), id) orelse return false;
    return true;
}

fn paramValueToText(_: *const clap.Plugin, id: u32, value: f64, buffer: [*]u8, capacity: u32) callconv(.c) bool {
    if (id >= core.num_params or capacity < 2) return false;
    const slice = buffer[0..capacity];
    if (id == core.ParamIndex.bypass) {
        const word = if (value >= 0.5) "On" else "Off";
        if (word.len + 1 > slice.len) return false;
        @memcpy(slice[0..word.len], word);
        slice[word.len] = 0;
        return true;
    }
    const formatted = std.fmt.bufPrint(slice[0 .. slice.len - 1], "{d} dB", .{value}) catch return false;
    slice[formatted.len] = 0;
    return true;
}

fn paramTextToValue(_: *const clap.Plugin, id: u32, text: [*:0]const u8, out: *f64) callconv(.c) bool {
    if (id >= core.num_params) return false;
    const raw = std.mem.trim(u8, std.mem.span(text), " \t");
    if (id == core.ParamIndex.bypass) {
        if (std.ascii.eqlIgnoreCase(raw, "On")) { out.* = 1; return true; }
        if (std.ascii.eqlIgnoreCase(raw, "Off")) { out.* = 0; return true; }
    }
    const number = if (std.mem.endsWith(u8, raw, "dB")) std.mem.trim(u8, raw[0 .. raw.len - 2], " \t") else raw;
    const value = std.fmt.parseFloat(f64, number) catch return false;
    if (!std.math.isFinite(value)) return false;
    out.* = value;
    return true;
}

fn paramFlush(plugin: *const clap.Plugin, inputs: *const clap.InputEvents, _: *const clap.OutputEvents) callconv(.c) void {
    flushEvents(instance(plugin), inputs);
}

const params = clap.Params{
    .count = paramCount,
    .get_info = paramInfo,
    .get_value = paramGetValue,
    .value_to_text = paramValueToText,
    .text_to_value = paramTextToValue,
    .flush = paramFlush,
};

// Versioned, little-endian state: "DZG1", gain bits, bypass bits.
fn stateSave(plugin: *const clap.Plugin, stream: *const clap.OutputStream) callconv(.c) bool {
    const self = instance(plugin);
    var bytes = [_]u8{ 'D', 'Z', 'G', '1' } ++ [_]u8{0} ** 8;
    for (0..core.num_params) |i| {
        const bits: u32 = @bitCast(self.dsp.params.getNormalized(@intCast(i)));
        for (0..4) |byte| {
            bytes[4 + i * 4 + byte] = @truncate(bits >> @intCast(byte * 8));
        }
    }
    var done: usize = 0;
    while (done < bytes.len) {
        const n = stream.write(stream, @ptrCast(&bytes[done]), @intCast(bytes.len - done));
        if (n <= 0 or @as(u64, @intCast(n)) > bytes.len - done) return false;
        done += @intCast(n);
    }
    return true;
}

fn stateLoad(plugin: *const clap.Plugin, stream: *const clap.InputStream) callconv(.c) bool {
    var bytes: [12]u8 = undefined;
    var done: usize = 0;
    while (done < bytes.len) {
        const n = stream.read(stream, @ptrCast(&bytes[done]), @intCast(bytes.len - done));
        if (n <= 0 or @as(u64, @intCast(n)) > bytes.len - done) return false;
        done += @intCast(n);
    }
    if (!std.mem.eql(u8, bytes[0..4], "DZG1")) return false;
    var values: [2]f32 = undefined;
    for (0..2) |i| {
        var bits: u32 = 0;
        for (0..4) |byte| bits |= @as(u32, bytes[4 + i * 4 + byte]) << @intCast(byte * 8);
        values[i] = @bitCast(bits);
        if (!std.math.isFinite(values[i]) or values[i] < 0 or values[i] > 1) return false;
    }
    const self = instance(plugin);
    for (0..2) |i| self.dsp.params.setNormalized(@intCast(i), values[i]);
    return true;
}

const state = clap.State{ .save = stateSave, .load = stateLoad };

fn factoryCount(_: *const clap.PluginFactory) callconv(.c) u32 {
    return 1;
}

fn factoryDescriptor(_: *const clap.PluginFactory, index: u32) callconv(.c) ?*const clap.Descriptor {
    return if (index == 0) &descriptor else null;
}

fn factoryCreate(_: *const clap.PluginFactory, _: *const clap.Host, id: [*:0]const u8) callconv(.c) ?*const clap.Plugin {
    if (!std.mem.eql(u8, std.mem.span(id), plugin_id)) return null;
    const self = std.heap.page_allocator.create(Instance) catch return null;
    self.* = .{
        .dsp = core.GainPlugin.init(48000),
        .plugin = .{
            .desc = &descriptor,
            .plugin_data = self,
            .init = pluginInit,
            .destroy = pluginDestroy,
            .activate = pluginActivate,
            .deactivate = pluginDeactivate,
            .start_processing = startProcessing,
            .stop_processing = stopProcessing,
            .reset = reset,
            .process = processAudio,
            .get_extension = getExtension,
            .on_main_thread = onMainThread,
        },
    };
    return &self.plugin;
}

const factory = clap.PluginFactory{
    .get_plugin_count = factoryCount,
    .get_plugin_descriptor = factoryDescriptor,
    .create_plugin = factoryCreate,
};

fn entryInit(_: [*:0]const u8) callconv(.c) bool {
    return true;
}

fn entryDeinit() callconv(.c) void {}

fn entryGetFactory(id: [*:0]const u8) callconv(.c) ?*const anyopaque {
    if (std.mem.eql(u8, std.mem.span(id), "clap.plugin-factory")) return @ptrCast(&factory);
    return null;
}

pub export var clap_entry: clap.Entry = .{
    .clap_version = .{},
    .init = entryInit,
    .deinit = entryDeinit,
    .get_factory = entryGetFactory,
};
