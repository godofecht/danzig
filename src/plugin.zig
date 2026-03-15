// VST3 Plugin Base Interface and Lifecycle Management

const std = @import("std");
const vst3 = @import("vst3.zig");

pub const Parameter = struct {
    id: u32,
    normalized: f64,
    plain: f64,
    title: [128]u8 = undefined,
    units: [64]u8 = undefined,
    minValue: f64 = 0.0,
    maxValue: f64 = 1.0,
    defaultValue: f64 = 0.5,
    stepCount: i32 = 0,
};

pub const ParameterMap = struct {
    allocator: std.mem.Allocator,
    params: std.AutoHashMap(u32, Parameter),

    pub fn init(allocator: std.mem.Allocator) ParameterMap {
        return ParameterMap{
            .allocator = allocator,
            .params = std.AutoHashMap(u32, Parameter).init(allocator),
        };
    }

    pub fn deinit(self: *ParameterMap) void {
        self.params.deinit();
    }

    pub fn add(self: *ParameterMap, param: Parameter) !void {
        try self.params.put(param.id, param);
    }

    pub fn get(self: ParameterMap, id: u32) ?Parameter {
        return self.params.get(id);
    }

    pub fn getNormalized(self: ParameterMap, id: u32) f64 {
        if (self.params.get(id)) |param| {
            return param.normalized;
        }
        return 0.0;
    }

    pub fn setNormalized(self: *ParameterMap, id: u32, value: f64) void {
        if (self.params.getPtr(id)) |param| {
            param.normalized = std.math.clamp(value, 0.0, 1.0);
            param.plain = denormalize(param.normalized, param.minValue, param.maxValue);
        }
    }

    pub fn count(self: ParameterMap) u32 {
        return @intCast(self.params.count());
    }

    pub fn iterator(self: *ParameterMap) std.AutoHashMap(u32, Parameter).Iterator {
        return self.params.iterator();
    }
};

pub fn normalize(plain: f64, min: f64, max: f64) f64 {
    if (max <= min) return 0.5;
    return (plain - min) / (max - min);
}

pub fn denormalize(normalized: f64, min: f64, max: f64) f64 {
    return min + (normalized * (max - min));
}

pub const AudioBusInfo = struct {
    active: bool = false,
    channelCount: u32 = 0,
    sampleRate: f64 = 44100.0,
};

pub const Plugin = struct {
    allocator: std.mem.Allocator,
    parameters: ParameterMap,
    sampleRate: f64 = 44100.0,
    active: bool = false,
    inputBus: AudioBusInfo = .{},
    outputBus: AudioBusInfo = .{},

    pub fn init(allocator: std.mem.Allocator) Plugin {
        return Plugin{
            .allocator = allocator,
            .parameters = ParameterMap.init(allocator),
        };
    }

    pub fn deinit(self: *Plugin) void {
        self.parameters.deinit();
    }

    pub fn addParameter(self: *Plugin, param: Parameter) !void {
        try self.parameters.add(param);
    }

    pub fn getParameterCount(self: Plugin) u32 {
        return self.parameters.count();
    }

    pub fn getParameterNormalized(self: Plugin, id: u32) f64 {
        return self.parameters.getNormalized(id);
    }

    pub fn setParameterNormalized(self: *Plugin, id: u32, value: f64) void {
        self.parameters.setNormalized(id, value);
    }

    pub fn setupProcessing(self: *Plugin, sampleRate: f64, _: u32) void {
        self.sampleRate = sampleRate;
        self.inputBus.sampleRate = sampleRate;
        self.outputBus.sampleRate = sampleRate;
    }

    pub fn activate(self: *Plugin) void {
        self.active = true;
    }

    pub fn deactivate(self: *Plugin) void {
        self.active = false;
    }

    pub fn process(self: *Plugin, inputs: []*[*]f32, outputs: []*[*]f32, numChannels: u32, numSamples: u32) void {
        if (!self.active or numChannels == 0) return;

        for (0..numChannels) |ch| {
            @memcpy(outputs[ch][0..numSamples], inputs[ch][0..numSamples]);
        }
    }
};

pub const PluginContext = struct {
    allocator: std.mem.Allocator,
    plugin: *Plugin,
    hostContext: ?*anyopaque = null,
    refCount: u32 = 1,

    pub fn init(allocator: std.mem.Allocator, plugin: *Plugin) PluginContext {
        return PluginContext{
            .allocator = allocator,
            .plugin = plugin,
        };
    }

    pub fn addRef(self: *PluginContext) u32 {
        self.refCount += 1;
        return self.refCount;
    }

    pub fn release(self: *PluginContext) u32 {
        self.refCount -= 1;
        return self.refCount;
    }
};
