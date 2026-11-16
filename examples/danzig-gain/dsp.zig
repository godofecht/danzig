// Shared host-neutral gain engine for VST3 and CLAP.
const danzig = @import("danzig");

pub const num_params = 2;

/// Index into the ParamStore. Also the VST3 ParamID, which keeps the mapping
/// between the two trivial.
pub const ParamIndex = struct {
    pub const gain: u32 = 0;
    pub const bypass: u32 = 1;
};

pub const gain_min_db: f32 = -48.0;
pub const gain_max_db: f32 = 48.0;
pub const gain_default_norm: f32 = 0.5; // 0 dB
pub const gain_smoothing_ms: f32 = 20.0;

// --- 1. DSP core -----------------------------------------------------------

/// The audio half of the plugin. No allocation, no locks, no VST3 types.
pub const GainPlugin = struct {
    params: danzig.ParamStore(num_params) = .{},
    sample_rate: f32 = 48000.0,

    pub fn init(sample_rate: f32) GainPlugin {
        var self = GainPlugin{ .sample_rate = sample_rate };
        _ = self.params.add(gain_min_db, gain_max_db, gain_default_norm, gain_smoothing_ms, sample_rate);
        // Bypass is a switch, so smoothing it would produce a half-bypassed
        // state that means nothing.
        _ = self.params.add(0.0, 1.0, 0.0, 0.0, sample_rate);
        return self;
    }

    /// Re-derive the smoothing coefficient. It is a function of the sample
    /// rate, so a rate change invalidates it.
    pub fn setSampleRate(self: *GainPlugin, sample_rate: f32) void {
        self.sample_rate = sample_rate;
        self.params.params[ParamIndex.gain].setSmoothingMs(gain_smoothing_ms, sample_rate);
        self.params.snapAll();
    }

    pub fn isBypassed(self: *const GainPlugin) bool {
        return self.params.getNormalized(ParamIndex.bypass) >= 0.5;
    }

    /// One sample of gain. The smoother is advanced even when bypassed so that
    /// leaving bypass does not jump to a stale value.
    pub fn nextGain(self: *GainPlugin, bypassed: bool) f32 {
        const db = self.params.tick(ParamIndex.gain);
        return if (bypassed) 1.0 else danzig.dBToLinear(db);
    }
};

