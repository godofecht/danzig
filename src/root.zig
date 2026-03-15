// Danzig VST3 Library Root

pub const vst3 = @import("vst3.zig");
pub const plugin = @import("plugin.zig");
pub const audio = @import("audio.zig");

pub const Plugin = plugin.Plugin;
pub const Parameter = plugin.Parameter;
pub const ParameterMap = plugin.ParameterMap;
pub const PluginContext = plugin.PluginContext;
pub const AudioBusInfo = plugin.AudioBusInfo;

pub const AudioBuffer = audio.AudioBuffer;
pub const GainProcessor = audio.GainProcessor;
pub const SimpleRamp = audio.SimpleRamp;

pub const normalize = plugin.normalize;
pub const denormalize = plugin.denormalize;
pub const dBToLinear = audio.dBToLinear;
pub const linearTodB = audio.linearTodB;
