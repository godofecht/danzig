// DanzigGain Standalone - Command-line audio processor
// Applies gain to WAV files using the danzig audio processing engine

const std = @import("std");
const danzig = @import("danzig");

const WavHeader = extern struct {
    riff: [4]u8 = "RIFF".*,
    size: u32,
    wave: [4]u8 = "WAVE".*,
    fmt: [4]u8 = "fmt ".*,
    fmt_size: u32 = 16,
    format: u16 = 1,
    channels: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bits_per_sample: u16 = 32,
    data: [4]u8 = "data".*,
    data_size: u32,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("Usage: danzig-gain-standalone <input.wav> <output.wav> <gain_db>\n", .{});
        std.debug.print("Example: danzig-gain-standalone input.wav output.wav 6.0\n", .{});
        return;
    }

    const input_path = args[1];
    const output_path = args[2];
    const gain_db = try std.fmt.parseFloat(f32, args[3]);

    if (gain_db < -48.0 or gain_db > 48.0) {
        std.debug.print("Error: Gain must be between -48 and +48 dB\n", .{});
        return error.InvalidGain;
    }

    var input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();

    var wav_header: WavHeader = undefined;
    const header_bytes = try input_file.readAll(std.mem.asBytes(&wav_header));
    if (header_bytes != @sizeOf(WavHeader)) {
        std.debug.print("Error: Could not read WAV header\n", .{});
        return error.InvalidWavFile;
    }

    if (!std.mem.eql(u8, &wav_header.riff, "RIFF") or
        !std.mem.eql(u8, &wav_header.wave, "WAVE")) {
        std.debug.print("Error: Not a valid WAV file\n", .{});
        return error.InvalidWavFile;
    }

    if (wav_header.format != 1 or wav_header.bits_per_sample != 32) {
        std.debug.print("Error: Only 32-bit float PCM WAV files are supported\n", .{});
        return error.UnsupportedFormat;
    }

    const num_channels = wav_header.channels;
    const sample_rate = wav_header.sample_rate;
    const data_size = wav_header.data_size;
    const num_samples = data_size / (4 * num_channels);

    std.debug.print("Processing audio:\n", .{});
    std.debug.print("  Channels: {d}\n", .{num_channels});
    std.debug.print("  Sample rate: {d} Hz\n", .{sample_rate});
    std.debug.print("  Samples: {d}\n", .{num_samples});
    std.debug.print("  Duration: {d:.2} seconds\n", .{@as(f32, @floatFromInt(num_samples)) / @as(f32, @floatFromInt(sample_rate))});
    std.debug.print("  Gain: {d:.1} dB\n", .{gain_db});

    const audio_data = try allocator.alloc(f32, data_size / 4);
    defer allocator.free(audio_data);

    const bytes_read = try input_file.readAll(std.mem.sliceAsBytes(audio_data));
    if (bytes_read != data_size) {
        std.debug.print("Error: Could not read audio data\n", .{});
        return error.IncompleteRead;
    }

    var gain_processor = danzig.GainProcessor{};
    gain_processor.setGain(gain_db);

    // Simple approach: process in-place using slice iteration
    const gain_linear = danzig.dBToLinear(gain_db);
    for (0..audio_data.len) |i| {
        audio_data[i] *= gain_linear;
    }

    var output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    try output_file.writeAll(std.mem.asBytes(&wav_header));
    try output_file.writeAll(std.mem.sliceAsBytes(audio_data));

    std.debug.print("\n✓ Successfully processed and saved to: {s}\n", .{output_path});
}
