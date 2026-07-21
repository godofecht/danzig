// Danzig Gain - Simple VST3 Gain Plugin Example
// Demonstrates danzig library usage with a stereo gain effect

const std = @import("std");
const danzig = @import("danzig");

// Plugin IDs - generated UUIDs (example)
const PLUGIN_UID = [16]u8{
    0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0,
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
};

const CONTROLLER_UID = [16]u8{
    0x87, 0x65, 0x43, 0x21, 0xf0, 0xed, 0xcb, 0xa9,
    0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11,
};

const ParamID = struct {
    pub const Gain: u32 = 0;
    pub const Bypass: u32 = 1;
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gPluginInstance: ?*GainPlugin = null;

pub const GainPlugin = struct {
    plugin: danzig.Plugin,
    gainProcessor: danzig.GainProcessor = .{},

    pub fn init(allocator: std.mem.Allocator) !*GainPlugin {
        const self = try allocator.create(GainPlugin);
        self.plugin = danzig.Plugin.init(allocator);
        self.gainProcessor = .{};

        // Add Gain parameter
        var gainParam = danzig.Parameter{
            .id = ParamID.Gain,
            .normalized = 0.5,
            .plain = 0.0,
            .title = undefined,
            .units = undefined,
            .minValue = -48.0,
            .maxValue = 48.0,
            .defaultValue = 0.0,
            .stepCount = 0,
        };
        @memcpy(gainParam.title[0..4], "Gain");
        @memcpy(gainParam.units[0..2], "dB");

        try self.plugin.addParameter(gainParam);

        return self;
    }

    pub fn deinit(self: *GainPlugin, allocator: std.mem.Allocator) void {
        self.plugin.deinit();
        allocator.destroy(self);
    }

    pub fn setupProcessing(self: *GainPlugin, sampleRate: f64) void {
        self.plugin.setupProcessing(sampleRate, 256);
    }

    pub fn activate(self: *GainPlugin) void {
        self.plugin.activate();
    }

    pub fn deactivate(self: *GainPlugin) void {
        self.plugin.deactivate();
    }

    pub fn setParameterNormalized(self: *GainPlugin, paramId: u32, normalized: f64) void {
        self.plugin.setParameterNormalized(paramId, normalized);
        if (paramId == ParamID.Gain) {
            const gainDb = danzig.denormalize(normalized, -48.0, 48.0);
            self.gainProcessor.setGain(@floatCast(gainDb));
        }
    }

    pub fn getParameterNormalized(self: GainPlugin, paramId: u32) f64 {
        return self.plugin.getParameterNormalized(paramId);
    }

    pub fn process(self: *GainPlugin, inputs: []*[*]f32, outputs: []*[*]f32, numChannels: u32, numSamples: u32) void {
        if (!self.plugin.active) {
            for (0..numChannels) |ch| {
                @memcpy(outputs[ch][0..numSamples], inputs[ch][0..numSamples]);
            }
            return;
        }

        self.gainProcessor.process(inputs, outputs, numChannels, numSamples);
    }
};

// VST3 Module Entry Points
// Minimal factory implementation for VST3 plugin loading

// Module Info used by VST3 hosts
pub const ModuleInfo = extern struct {
    name: [*:0]const u8 = "Danzig Gain",
    vendor: [*:0]const u8 = "Superelectric",
    url: [*:0]const u8 = "https://superelectric.dev",
    email: [*:0]const u8 = "danzig@superelectric.dev",
    version: u32 = 0x00010000,
    sdkVersion: u32 = 0x00030600,
};

const IUnknownVTable = extern struct {
    queryInterface: *const fn (*anyopaque, guid: [*]const u8, obj: *?*anyopaque) callconv(.c) i32,
    addRef: *const fn (*anyopaque) callconv(.c) u32,
    release: *const fn (*anyopaque) callconv(.c) u32,
};

const IPluginFactoryVTable = extern struct {
    base: IUnknownVTable,
    getFactoryInfo: *const fn (*anyopaque, info: *anyopaque) callconv(.c) i32,
    countClasses: *const fn (*anyopaque) callconv(.c) i32,
    getClassInfo: *const fn (*anyopaque, index: i32, info: *anyopaque) callconv(.c) i32,
    createInstance: *const fn (*anyopaque, cid: [*]const u8, iid: [*]const u8, obj: *?*anyopaque) callconv(.c) i32,
};

pub const PluginFactory = extern struct {
    vtbl: [*]*IPluginFactoryVTable,
    refCount: u32 = 1,
};

var gFactory: PluginFactory = undefined;

fn factory_queryInterface(self: *anyopaque, guid: [*]const u8, obj: *?*anyopaque) callconv(.c) i32 {
    _ = self;
    _ = guid;
    _ = obj;
    return -1; // kNoInterface
}

fn factory_addRef(self: *anyopaque) callconv(.c) u32 {
    var factory = @as(*PluginFactory, @ptrCast(@alignCast(self)));
    factory.refCount += 1;
    return factory.refCount;
}

fn factory_release(self: *anyopaque) callconv(.c) u32 {
    var factory = @as(*PluginFactory, @ptrCast(@alignCast(self)));
    if (factory.refCount > 0) factory.refCount -= 1;
    return factory.refCount;
}

fn factory_getFactoryInfo(self: *anyopaque, _: *anyopaque) callconv(.c) i32 {
    _ = self;
    return 0;
}

fn factory_countClasses(_: *anyopaque) callconv(.c) i32 {
    return 1;
}

fn factory_getClassInfo(_: *anyopaque, index: i32, _: *anyopaque) callconv(.c) i32 {
    _ = index;
    return 0;
}

fn factory_createInstance(_: *anyopaque, _: [*]const u8, _: [*]const u8, _: *?*anyopaque) callconv(.c) i32 {
    return 0;
}

var factoryVtable: IPluginFactoryVTable = .{
    .base = .{
        .queryInterface = factory_queryInterface,
        .addRef = factory_addRef,
        .release = factory_release,
    },
    .getFactoryInfo = factory_getFactoryInfo,
    .countClasses = factory_countClasses,
    .getClassInfo = factory_getClassInfo,
    .createInstance = factory_createInstance,
};

export fn GetPluginFactory() ?*anyopaque {
    gFactory.vtbl = @ptrCast(&factoryVtable);
    return @ptrCast(&gFactory);
}

pub fn main() !void {
    std.debug.print("Danzig Gain Plugin - Zig VST3 Framework\n", .{});
    std.debug.print("This is a VST3 plugin library and should not be run directly.\n", .{});
}
