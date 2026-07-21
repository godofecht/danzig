// danzig-minimal: the smallest useful danzig plugin.
//
// This is the file to copy when starting a new plugin. It is deliberately
// smaller than examples/danzig-gain: one parameter, one line of DSP, and the
// single symbol a VST3 host looks for. Everything else is comment.
//
// The same source builds two things:
//
//   zig build              -> zig-out/lib/libDanzigMinimal.dylib  (the plugin)
//   zig build run-minimal  -> runs main() below over a test signal
//
// Building it as an executable as well means you can hear-check the maths
// without opening a DAW.

const std = @import("std");
const danzig = @import("danzig");

// --- 1. Parameters ---------------------------------------------------------
//
// Parameters live in a ParamStore, a fixed-size array of cache-line-sized
// atomic slots. Nothing here allocates, so it is safe to read from the audio
// thread. Indices are assigned in registration order; name them.

const ParamIndex = struct {
    pub const trim: u32 = 0;
};

const num_params = 1;

// --- 2. The plugin ---------------------------------------------------------

pub const MinimalPlugin = struct {
    params: danzig.ParamStore(num_params) = .{},
    sample_rate: f32 = 48000.0,

    /// Register parameters. Called once, off the audio thread.
    ///
    /// Arguments are (min, max, default_normalized, smoothing_ms, sample_rate).
    /// The smoothing time turns a parameter jump into a one-pole ramp, which is
    /// what stops a slider drag from producing clicks.
    pub fn init(sample_rate: f32) MinimalPlugin {
        var self = MinimalPlugin{ .sample_rate = sample_rate };
        const idx = self.params.add(-24.0, 24.0, 0.5, 20.0, sample_rate);
        std.debug.assert(idx == ParamIndex.trim);
        return self;
    }

    /// The host thread writes here. Lock-free, so it never blocks audio.
    pub fn setParameter(self: *MinimalPlugin, index: u32, normalized: f32) void {
        self.params.setNormalized(index, normalized);
    }

    /// The audio callback. No allocation, no locks, no syscalls.
    ///
    /// `tick` advances the smoother by one sample and returns the plain value,
    /// so the gain is recomputed per sample rather than per block.
    pub fn process(
        self: *MinimalPlugin,
        input: []const []const f32,
        output: []const []f32,
        frames: usize,
    ) void {
        for (0..frames) |i| {
            const gain = danzig.dBToLinear(self.params.tick(ParamIndex.trim));
            for (input, output) |in_ch, out_ch| {
                out_ch[i] = in_ch[i] * gain;
            }
        }
    }
};

// --- 3. The VST3 entry point ----------------------------------------------
//
// A VST3 binary exports exactly one symbol. The host calls it, reads the first
// word of the returned pointer as a vtable pointer, and calls through that.
// See examples/danzig-gain for a factory with a real vtable behind it; this
// one returns null, which a host reads as "no classes here".

export fn GetPluginFactory() ?*anyopaque {
    return null;
}

// --- 4. Offline demo -------------------------------------------------------
//
// Feeds a full-scale DC signal through the plugin at three trim settings and
// prints the measured output level. DC makes the gain readable directly off
// the last sample.

fn runAt(normalized: f32, label: []const u8) void {
    var plugin = MinimalPlugin.init(48000.0);
    plugin.setParameter(ParamIndex.trim, normalized);

    const frames = 24000; // 500 ms, well past the 20 ms smoother's settling time
    var left_in = [_]f32{1.0} ** frames;
    var right_in = [_]f32{1.0} ** frames;
    var left_out = [_]f32{0.0} ** frames;
    var right_out = [_]f32{0.0} ** frames;

    const input = [_][]const f32{ &left_in, &right_in };
    const output = [_][]f32{ &left_out, &right_out };

    plugin.process(&input, &output, frames);

    const settled = left_out[frames - 1];
    std.debug.print(
        "  {s:<12} normalized {d:.2}  ->  {d:>7.2} dB  (output {d:.4})\n",
        .{ label, normalized, danzig.linearTodB(settled), settled },
    );
}

pub fn main() void {
    std.debug.print("danzig-minimal: one parameter, one line of DSP\n\n", .{});
    std.debug.print("Trim range is -24 to +24 dB, 20 ms smoothing, 48 kHz.\n\n", .{});

    runAt(0.0, "full cut");
    runAt(0.5, "unity");
    runAt(1.0, "full boost");

    std.debug.print("\nCopy examples/danzig-minimal/root.zig to start your own plugin.\n", .{});
}
