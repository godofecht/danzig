// Unit tests for the pure-Zig core: audio math, gain staging, ramps, and the
// lock-free parameter store.
//
// These complement examples/danzig-test, which exercises the built plugin
// through the raw VST3 C ABI. This file needs no artifact and no host.

const std = @import("std");
const testing = std.testing;

const audio = @import("audio.zig");
const plugin = @import("plugin.zig");

// --- dB <-> linear ---------------------------------------------------------
//
// These two guard a real regression: a copy of this file once carried a stray
// `* 10.0` in the exponent, which turned dBToLinear(6) into 1000.0 instead of
// 1.9953. The round-trip test below is what catches that class of drift.

test "dBToLinear: unity at 0 dB" {
    try testing.expectApproxEqAbs(@as(f32, 1.0), audio.dBToLinear(0.0), 1e-6);
}

test "dBToLinear: +6 dB is a factor of ~2" {
    try testing.expectApproxEqAbs(@as(f32, 1.99526), audio.dBToLinear(6.0), 1e-4);
}

test "dBToLinear: -6 dB is a factor of ~0.5" {
    try testing.expectApproxEqAbs(@as(f32, 0.501187), audio.dBToLinear(-6.0), 1e-4);
}

test "dBToLinear: +20 dB is exactly a factor of 10" {
    try testing.expectApproxEqAbs(@as(f32, 10.0), audio.dBToLinear(20.0), 1e-4);
}

test "linearTodB: unity is 0 dB" {
    try testing.expectApproxEqAbs(@as(f32, 0.0), audio.linearTodB(1.0), 1e-6);
}

test "linearTodB: factor of 10 is +20 dB" {
    try testing.expectApproxEqAbs(@as(f32, 20.0), audio.linearTodB(10.0), 1e-4);
}

test "linearTodB: non-positive input floors at -80 dB" {
    try testing.expectEqual(@as(f32, -80.0), audio.linearTodB(0.0));
    try testing.expectEqual(@as(f32, -80.0), audio.linearTodB(-1.0));
}

test "dB round-trip is identity across the useful range" {
    const cases = [_]f32{ -48.0, -24.0, -12.0, -6.0, 0.0, 6.0, 12.0, 24.0 };
    for (cases) |dB| {
        const round_tripped = audio.linearTodB(audio.dBToLinear(dB));
        try testing.expectApproxEqAbs(dB, round_tripped, 1e-3);
    }
}

// --- interpolation and clamping -------------------------------------------

test "linearInterpolate: endpoints and midpoint" {
    try testing.expectApproxEqAbs(@as(f32, 0.0), audio.linearInterpolate(0.0, 10.0, 0.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 10.0), audio.linearInterpolate(0.0, 10.0, 1.0), 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 5.0), audio.linearInterpolate(0.0, 10.0, 0.5), 1e-6);
}

test "clamp: below, inside, above" {
    try testing.expectEqual(@as(f32, 0.0), audio.clamp(-1.0, 0.0, 1.0));
    try testing.expectEqual(@as(f32, 0.5), audio.clamp(0.5, 0.0, 1.0));
    try testing.expectEqual(@as(f32, 1.0), audio.clamp(2.0, 0.0, 1.0));
}

// --- AudioBuffer -----------------------------------------------------------

test "AudioBuffer: init zeroes every channel" {
    var buf = try audio.AudioBuffer.init(testing.allocator, 2, 64, 48000.0);
    defer buf.deinit(testing.allocator);

    try testing.expectEqual(@as(u32, 2), buf.channelCount);
    try testing.expectEqual(@as(u32, 64), buf.sampleCount);
    try testing.expectEqual(@as(f64, 48000.0), buf.sampleRate);

    for (0..buf.channelCount) |ch| {
        for (buf.data[ch][0..buf.sampleCount]) |sample| {
            try testing.expectEqual(@as(f32, 0.0), sample);
        }
    }
}

test "AudioBuffer: clear resets written samples" {
    var buf = try audio.AudioBuffer.init(testing.allocator, 1, 16, 44100.0);
    defer buf.deinit(testing.allocator);

    for (0..16) |s| buf.data[0][s] = 0.75;
    buf.clear();

    for (buf.data[0][0..16]) |sample| {
        try testing.expectEqual(@as(f32, 0.0), sample);
    }
}

// --- GainProcessor ---------------------------------------------------------

test "GainProcessor: setGain converts dB to a linear target" {
    var g = audio.GainProcessor{};
    g.setGain(6.0);
    try testing.expectApproxEqAbs(@as(f32, 1.99526), g.targetGain, 1e-4);
}

test "GainProcessor: normalized gain round-trips through the 96 dB range" {
    var g = audio.GainProcessor{};
    // 0.5 normalized maps to (0.5 * 96) - 48 = 0 dB, i.e. unity.
    g.setNormalizedGain(0.5);
    try testing.expectApproxEqAbs(@as(f32, 1.0), g.targetGain, 1e-4);
}

test "GainProcessor: normalized gain clamps out-of-range input" {
    var g = audio.GainProcessor{};
    g.setNormalizedGain(2.0);
    const at_max = g.targetGain;
    g.setNormalizedGain(1.0);
    try testing.expectApproxEqAbs(at_max, g.targetGain, 1e-6);
}

test "GainProcessor: process ramps toward the target rather than jumping" {
    var g = audio.GainProcessor{};
    g.setGain(0.0); // unity target
    g.gain = 0.0; // start silent

    var in_data = [_]f32{1.0} ** 32;
    var out_data = [_]f32{0.0} ** 32;
    var inputs = [_][*]f32{&in_data};
    var outputs = [_][*]f32{&out_data};

    g.process(&inputs, &outputs, 1, 32);

    // Gain climbs from 0 toward 1, so output rises monotonically and stays
    // strictly below the input.
    try testing.expect(out_data[0] < out_data[31]);
    try testing.expect(out_data[31] < 1.0);
    try testing.expect(g.gain > 0.0);
}

// --- SimpleRamp ------------------------------------------------------------

test "SimpleRamp: a zero-length ramp is treated as instant" {
    var r = audio.SimpleRamp.init(0.0, 0);
    r.setTarget(1.0);
    try testing.expectEqual(@as(f32, 1.0), r.next());
}

test "SimpleRamp: reaches its target by the final sample" {
    var r = audio.SimpleRamp.init(0.0, 8);
    r.setTarget(1.0);
    var last: f32 = 0.0;
    for (0..8) |_| last = r.next();
    try testing.expectApproxEqAbs(@as(f32, 1.0), last, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), r.getValue(), 1e-6);
}

test "SimpleRamp: setTarget restarts the ramp" {
    var r = audio.SimpleRamp.init(0.0, 4);
    r.setTarget(1.0);
    _ = r.next();
    r.setTarget(2.0);
    try testing.expectEqual(@as(u32, 0), r.currentSample);
    try testing.expectEqual(@as(f32, 2.0), r.targetValue);
}

// --- normalize / denormalize ----------------------------------------------

test "normalize: maps a plain value into [0, 1]" {
    try testing.expectApproxEqAbs(@as(f64, 0.0), plugin.normalize(-48.0, -48.0, 48.0), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 0.5), plugin.normalize(0.0, -48.0, 48.0), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 1.0), plugin.normalize(48.0, -48.0, 48.0), 1e-9);
}

test "normalize: degenerate range returns the midpoint" {
    try testing.expectEqual(@as(f64, 0.5), plugin.normalize(5.0, 1.0, 1.0));
    try testing.expectEqual(@as(f64, 0.5), plugin.normalize(5.0, 2.0, 1.0));
}

test "denormalize inverts normalize" {
    const cases = [_]f64{ -48.0, -12.0, 0.0, 12.0, 48.0 };
    for (cases) |plain| {
        const n = plugin.normalize(plain, -48.0, 48.0);
        try testing.expectApproxEqAbs(plain, plugin.denormalize(n, -48.0, 48.0), 1e-9);
    }
}
