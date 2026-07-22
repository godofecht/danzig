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

var gpa = std.heap.DebugAllocator(.{}){};
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

export fn GetPluginFactory() ?*anyopaque {
    return null;
}

pub fn main() !void {
    std.debug.print("Danzig Gain Plugin - Zig VST3 Framework\n", .{});
    std.debug.print("This is a VST3 plugin library and should not be run directly.\n", .{});
}
