// CoreAudio device enumeration for macOS
// Uses AudioObjectGetPropertyData to list available audio devices

const std = @import("std");
const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
});

pub const AudioDevice = struct {
    id: u32,
    name: [256]u8 = undefined,
    name_len: usize = 0,
    is_input: bool = false,
    is_output: bool = false,
    is_default: bool = false,
};

fn getStringProperty(device_id: u32, selector: u32, buf: []u8) ?[]u8 {
    var cf_string: c.CFStringRef = null;
    var size: u32 = @sizeOf(c.CFStringRef);
    var address = c.AudioObjectPropertyAddress{
        .mSelector = selector,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    };

    const status = c.AudioObjectGetPropertyData(device_id, &address, 0, null, &size, @ptrCast(&cf_string));
    if (status != 0 or cf_string == null) return null;
    defer c.CFRelease(cf_string);

    if (c.CFStringGetCString(cf_string, buf.ptr, @intCast(buf.len), c.kCFStringEncodingUTF8) != 0) {
        const len = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len;
        return buf[0..len];
    }
    return null;
}

fn getChannelCount(device_id: u32, scope: u32) u32 {
    var size: u32 = 0;
    var address = c.AudioObjectPropertyAddress{
        .mSelector = c.kAudioDevicePropertyStreamConfiguration,
        .mScope = scope,
        .mElement = c.kAudioObjectPropertyElementMain,
    };

    var status = c.AudioObjectGetPropertyDataSize(device_id, &address, 0, null, &size);
    if (status != 0 or size == 0) return 0;

    var buf: [4096]u8 align(@alignOf(c.AudioBufferList)) = undefined;
    if (size > buf.len) return 0;

    status = c.AudioObjectGetPropertyData(device_id, &address, 0, null, &size, &buf);
    if (status != 0) return 0;

    const list: *const c.AudioBufferList = @ptrCast(&buf);
    var channels: u32 = 0;
    for (0..list.mNumberBuffers) |i| {
        const buffers: [*]const c.AudioBuffer = &list.mBuffers;
        channels += buffers[i].mNumberChannels;
    }
    return channels;
}

fn getDefaultDevice(scope: u32) u32 {
    const selector: u32 = if (scope == c.kAudioDevicePropertyScopeInput)
        c.kAudioHardwarePropertyDefaultInputDevice
    else
        c.kAudioHardwarePropertyDefaultOutputDevice;

    var device_id: u32 = 0;
    var size: u32 = @sizeOf(u32);
    var address = c.AudioObjectPropertyAddress{
        .mSelector = selector,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    };

    const status = c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, &device_id);
    if (status != 0) return 0;
    return device_id;
}

pub fn enumerateDevices(allocator: std.mem.Allocator) ![]AudioDevice {
    // Get device count
    var size: u32 = 0;
    var address = c.AudioObjectPropertyAddress{
        .mSelector = c.kAudioHardwarePropertyDevices,
        .mScope = c.kAudioObjectPropertyScopeGlobal,
        .mElement = c.kAudioObjectPropertyElementMain,
    };

    var status = c.AudioObjectGetPropertyDataSize(c.kAudioObjectSystemObject, &address, 0, null, &size);
    if (status != 0) return error.CoreAudioError;

    const device_count = size / @sizeOf(u32);
    if (device_count == 0) return &[_]AudioDevice{};

    const device_ids = try allocator.alloc(u32, device_count);
    defer allocator.free(device_ids);

    status = c.AudioObjectGetPropertyData(c.kAudioObjectSystemObject, &address, 0, null, &size, device_ids.ptr);
    if (status != 0) return error.CoreAudioError;

    const default_input = getDefaultDevice(c.kAudioDevicePropertyScopeInput);
    const default_output = getDefaultDevice(c.kAudioDevicePropertyScopeOutput);

    // Unmanaged form: Zig 0.15 made ArrayList unmanaged by default and
    // dropped .init(allocator). ArrayListUnmanaged spells the same type in
    // both 0.14 and 0.15, so the allocator is passed per call instead.
    var devices: std.ArrayListUnmanaged(AudioDevice) = .{};

    for (device_ids) |did| {
        const input_channels = getChannelCount(did, c.kAudioDevicePropertyScopeInput);
        const output_channels = getChannelCount(did, c.kAudioDevicePropertyScopeOutput);

        // Skip devices with no audio channels
        if (input_channels == 0 and output_channels == 0) continue;

        var dev = AudioDevice{
            .id = did,
            .is_input = input_channels > 0,
            .is_output = output_channels > 0,
            .is_default = (did == default_input) or (did == default_output),
        };

        if (getStringProperty(did, c.kAudioObjectPropertyName, &dev.name)) |name| {
            dev.name_len = name.len;
        } else {
            const fallback = "Unknown Device";
            @memcpy(dev.name[0..fallback.len], fallback);
            dev.name_len = fallback.len;
        }

        try devices.append(allocator, dev);
    }

    return devices.toOwnedSlice(allocator);
}

pub fn devicesToJson(allocator: std.mem.Allocator, devices: []const AudioDevice) ![]u8 {
    var json: std.ArrayListUnmanaged(u8) = .{};
    var w = json.writer(allocator);

    try w.writeAll("{\"inputs\":[");
    var first_in = true;
    for (devices) |d| {
        if (!d.is_input) continue;
        if (!first_in) try w.writeAll(",");
        first_in = false;
        try w.print("{{\"id\":\"{d}\",\"name\":\"{s}\",\"isDefault\":{s}}}", .{
            d.id,
            d.name[0..d.name_len],
            if (d.is_default) "true" else "false",
        });
    }
    try w.writeAll("],\"outputs\":[");
    var first_out = true;
    for (devices) |d| {
        if (!d.is_output) continue;
        if (!first_out) try w.writeAll(",");
        first_out = false;
        try w.print("{{\"id\":\"{d}\",\"name\":\"{s}\",\"isDefault\":{s}}}", .{
            d.id,
            d.name[0..d.name_len],
            if (d.is_default) "true" else "false",
        });
    }
    try w.writeAll("]}");

    return json.toOwnedSlice(allocator);
}
