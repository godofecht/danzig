// Black-box CLAP ABI smoke test: factory, parameters, state extension, audio, automation.
const std = @import("std");
const clap = @import("danzig").clap;
extern var clap_entry: clap.Entry;

const automation = clap.EventParamValue{
    .header = .{
        .size = @sizeOf(clap.EventParamValue),
        .time = 0,
        .space_id = 0,
        .@"type" = clap.event_param_value,
        .flags = 0,
    },
    .param_id = 0,
    .cookie = null,
    .note_id = -1,
    .port_index = -1,
    .channel = -1,
    .key = -1,
    .value = -6.0,
};

fn eventCount(_: *const clap.InputEvents) callconv(.c) u32 {
    return 1;
}

fn eventGet(_: *const clap.InputEvents, index: u32) callconv(.c) ?*const clap.EventHeader {
    return if (index == 0) &automation.header else null;
}

const in_events = clap.InputEvents{
    .ctx = null,
    .size = eventCount,
    .get = eventGet,
};

pub fn main() !void {
    const testing = std.testing;
    try testing.expect(clap_entry.init("DanzigGain.clap"));
    defer clap_entry.deinit();

    const raw = clap_entry.get_factory("clap.plugin-factory") orelse return error.FactoryNotFound;
    const factory: *const clap.PluginFactory = @ptrCast(@alignCast(raw));
    try testing.expectEqual(@as(u32, 1), factory.get_plugin_count(factory));
    const desc = factory.get_plugin_descriptor(factory, 0) orelse return error.MissingDescriptor;
    try testing.expectEqualStrings("Danzig Gain", std.mem.span(desc.name));
    try testing.expect(factory.get_plugin_descriptor(factory, 1) == null);

    // The example CLAP adapter never dereferences the host pointer.
    var host_storage: u8 = 0;
    const host: *const clap.Host = @ptrCast(&host_storage);
    const plugin = factory.create_plugin(factory, host, desc.id) orelse return error.CannotCreate;
    defer plugin.destroy(plugin);
    try testing.expect(plugin.init(plugin));

    const params_raw = plugin.get_extension(plugin, "clap.params") orelse return error.ParamsMissing;
    const params: *const clap.Params = @ptrCast(@alignCast(params_raw));
    try testing.expectEqual(@as(u32, 2), params.count(plugin));
    var info: clap.ParamInfo = undefined;
    try testing.expect(params.get_info(plugin, 1, &info));
    try testing.expect((info.flags & clap.param_bypass) != 0);

    const ports_raw = plugin.get_extension(plugin, "clap.audio-ports") orelse return error.PortsMissing;
    const ports: *const clap.AudioPorts = @ptrCast(@alignCast(ports_raw));
    try testing.expectEqual(@as(u32, 1), ports.count(plugin, true));
    var port_info: clap.PortInfo = undefined;
    try testing.expect(ports.get(plugin, 0, false, &port_info));
    try testing.expectEqual(@as(u32, 2), port_info.channel_count);

    try testing.expect(plugin.activate(plugin, 48000.0, 1, 512));
    defer plugin.deactivate(plugin);
    try testing.expect(plugin.start_processing(plugin));
    defer plugin.stop_processing(plugin);

    var left_in = [_]f32{1.0} ** 32;
    var right_in = [_]f32{0.5} ** 32;
    var left_out = [_]f32{0.0} ** 32;
    var right_out = [_]f32{0.0} ** 32;
    var inputs = [_][*]f32{ &left_in, &right_in };
    var outputs = [_][*]f32{ &left_out, &right_out };
    var input_bus = [_]clap.AudioBuffer{.{
        .data32 = &inputs,
        .data64 = null,
        .channel_count = 2,
        .latency = 0,
        .constant_mask = 0,
    }};
    var output_bus = [_]clap.AudioBuffer{.{
        .data32 = &outputs,
        .data64 = null,
        .channel_count = 2,
        .latency = 0,
        .constant_mask = 0,
    }};
    const block = clap.Process{
        .steady_time = 0,
        .frames_count = 32,
        .transport = null,
        .audio_inputs = &input_bus,
        .audio_outputs = &output_bus,
        .audio_inputs_count = 1,
        .audio_outputs_count = 1,
        .in_events = &in_events,
        .out_events = null,
    };
    try testing.expectEqual(clap.process_continue, plugin.process(plugin, &block));
    try testing.expect(left_out[0] < 1.0);
    try testing.expect(left_out[31] < left_out[0]);
    try testing.expectApproxEqAbs(left_out[31] * 0.5, right_out[31], 0.0001);

    var value: f64 = 0;
    try testing.expect(params.get_value(plugin, 0, &value));
    try testing.expectApproxEqAbs(@as(f64, -6.0), value, 0.0001);
}
