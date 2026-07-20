// Audio utilities for DSP and buffer handling

const std = @import("std");

pub const AudioBuffer = struct {
    channelCount: u32,
    sampleCount: u32,
    sampleRate: f64,
    data: [][*]f32,

    pub fn init(allocator: std.mem.Allocator, channelCount: u32, sampleCount: u32, sampleRate: f64) !AudioBuffer {
        const data = try allocator.alloc([*]f32, channelCount);
        for (0..channelCount) |ch| {
            const channel = try allocator.alloc(f32, sampleCount);
            @memset(channel, 0);
            data[ch] = channel.ptr;
        }
        return AudioBuffer{
            .channelCount = channelCount,
            .sampleCount = sampleCount,
            .sampleRate = sampleRate,
            .data = data,
        };
    }

    pub fn deinit(self: AudioBuffer, allocator: std.mem.Allocator) void {
        for (0..self.channelCount) |ch| {
            const slice = self.data[ch][0..self.sampleCount];
            allocator.free(slice);
        }
        allocator.free(self.data);
    }

    pub fn clear(self: AudioBuffer) void {
        for (0..self.channelCount) |ch| {
            const slice = self.data[ch][0..self.sampleCount];
            @memset(slice, 0);
        }
    }

    pub fn silence(self: AudioBuffer) void {
        self.clear();
    }
};

pub fn linearInterpolate(x0: f32, x1: f32, t: f32) f32 {
    return x0 * (1.0 - t) + x1 * t;
}

pub fn clamp(value: f32, min: f32, max: f32) f32 {
    return std.math.clamp(value, min, max);
}

pub fn dBToLinear(dB: f32) f32 {
    // 10^(dB/20) = e^(dB * ln(10)/20)
    return @exp(dB * 0.11512925464970229);
}

pub fn linearTodB(linear: f32) f32 {
    // 20 * log10(linear) = 20/ln(10) * ln(linear)
    if (linear <= 0.0) return -80.0;
    return @log(linear) * 8.6858896380650365;
}

pub const GainProcessor = struct {
    gain: f32 = 1.0,
    targetGain: f32 = 1.0,

    pub fn setGain(self: *GainProcessor, gainDb: f32) void {
        self.targetGain = dBToLinear(gainDb);
    }

    pub fn process(self: *GainProcessor, inputs: [][*]f32, outputs: [][*]f32, channelCount: u32, numSamples: u32) void {
        for (0..channelCount) |ch| {
            for (0..numSamples) |s| {
                self.gain = linearInterpolate(self.gain, self.targetGain, 0.001);
                outputs[ch][s] = inputs[ch][s] * self.gain;
            }
        }
    }

    pub fn getNormalizedGain(self: GainProcessor) f32 {
        const db = linearTodB(self.gain);
        return clamp((db + 48.0) / 96.0, 0.0, 1.0);
    }

    pub fn setNormalizedGain(self: *GainProcessor, normalized: f32) void {
        const clamped = clamp(normalized, 0.0, 1.0);
        const db = (clamped * 96.0) - 48.0;
        self.setGain(db);
    }
};

pub const SimpleRamp = struct {
    currentValue: f32,
    targetValue: f32,
    rampSamples: u32,
    currentSample: u32 = 0,

    pub fn init(initialValue: f32, rampSamples: u32) SimpleRamp {
        return SimpleRamp{
            .currentValue = initialValue,
            .targetValue = initialValue,
            .rampSamples = if (rampSamples > 0) rampSamples else 1,
        };
    }

    pub fn setTarget(self: *SimpleRamp, target: f32) void {
        self.targetValue = target;
        self.currentSample = 0;
    }

    pub fn next(self: *SimpleRamp) f32 {
        if (self.rampSamples <= 1) {
            self.currentValue = self.targetValue;
            return self.currentValue;
        }

        const alpha = @as(f32, @floatFromInt(self.currentSample)) / @as(f32, @floatFromInt(self.rampSamples));
        self.currentValue = linearInterpolate(self.currentValue, self.targetValue, alpha);

        if (self.currentSample < self.rampSamples - 1) {
            self.currentSample += 1;
        } else {
            self.currentValue = self.targetValue;
        }

        return self.currentValue;
    }

    pub fn getValue(self: SimpleRamp) f32 {
        return self.currentValue;
    }
};
