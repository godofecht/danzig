# Danzig: A Lightweight Zig VST3 Plugin Framework

Danzig is a minimal, modern VST3 plugin development framework written entirely in Zig. It provides essential abstractions for building VST3 plugins without external dependencies, leveraging only the Zig standard library.

## Features

- **Zero External Dependencies**: Uses only Zig stdlib and VST3 C ABI
- **Type-Safe Abstractions**: Strong typing for parameters, audio processing, and plugin lifecycle
- **Memory Efficient**: Lightweight parameter management and audio buffer handling
- **Cross-Platform**: Works on macOS, Linux, and Windows (VST3 ABI)
- **Built with Azazel**: Integrates seamlessly with the azazel build system
- **DSP Utilities**: Includes gain processing, ramping, and audio math helpers

## Project Structure

```
src/danzig/
├── root.zig           # Public API exports
├── vst3.zig          # VST3 C interface bindings
├── plugin.zig        # Plugin base class and parameter system
└── audio.zig         # Audio processing utilities

examples/danzig-gain/
└── root.zig          # Example stereo gain effect plugin
```

## Core Components

### VST3 Bindings (`vst3.zig`)
Complete C ABI declarations for VST3 interfaces:
- `IUnknown`, `IPluginBase`, `IComponent`
- `IAudioProcessor` for audio processing
- `IEditController` for parameter handling
- `ProcessData`, `ProcessContext`, and audio structures
- Type definitions and constants for VST3 development

### Plugin Framework (`plugin.zig`)
The main abstraction layer:

#### Parameter System
```zig
pub const Parameter = struct {
    id: u32,
    normalized: f64,           // 0.0 to 1.0
    plain: f64,                // Actual value
    title: [128]u8,
    units: [64]u8,
    minValue: f64,
    maxValue: f64,
    defaultValue: f64,
};

pub const ParameterMap = struct {
    // Efficient parameter storage and lookup
    pub fn add(self: *ParameterMap, param: Parameter) !void
    pub fn setNormalized(self: *ParameterMap, id: u32, value: f64) void
    pub fn getNormalized(self: ParameterMap, id: u32) f64
    pub fn get(self: ParameterMap, id: u32) ?Parameter
};
```

#### Plugin Base Class
```zig
pub const Plugin = struct {
    parameters: ParameterMap,
    sampleRate: f64,
    active: bool,
    
    pub fn init(allocator: std.mem.Allocator) Plugin
    pub fn addParameter(self: *Plugin, param: Parameter) !void
    pub fn setupProcessing(self: *Plugin, sampleRate: f64, maxSamplesPerBlock: u32) void
    pub fn activate(self: *Plugin) void
    pub fn deactivate(self: *Plugin) void
    pub fn process(self: *Plugin, inputs: []*[*]f32, outputs: []*[*]f32, numChannels: u32, numSamples: u32) void
};
```

### Audio Utilities (`audio.zig`)
DSP and audio processing helpers:

- **GainProcessor**: Smooth gain application with dB conversion
- **SimpleRamp**: Linear ramping for parameter changes
- **AudioBuffer**: Memory-efficient multi-channel audio buffer
- **Math Utilities**: `dBToLinear`, `linearTodB`, `clamp`, `linearInterpolate`

Example:
```zig
var gainProc = GainProcessor{};
gainProc.setGain(-6.0);  // -6dB
gainProc.process(inputs, outputs, 2, numSamples);
```

## Example: Danzig Gain Plugin

The `examples/danzig-gain` directory contains a complete stereo gain effect demonstrating the framework:

```zig
pub const GainPlugin = struct {
    params: danzig.ParamStore(2),
    sample_rate: f32,

    pub fn init(sample_rate: f32) GainPlugin
    pub fn setSampleRate(self: *GainPlugin, sample_rate: f32) void
    pub fn isBypassed(self: *const GainPlugin) bool
    pub fn nextGain(self: *GainPlugin, bypassed: bool) f32
};
```

The rest of the file wraps that core in the VST3 C ABI: one object exposing
IComponent, IAudioProcessor and IEditController, a static IPluginFactory, and
the module entry points (`GetPluginFactory`, `bundleEntry`) a host looks for.

### Parameter IDs
- `ParamIndex.gain = 0`: Gain in dB (-48 to +48)
- `ParamIndex.bypass = 1`: Bypass toggle

### Building
```bash
zig build
```

This produces:
- `zig-out/lib/libdanzig.a`: Danzig library (static)
- `zig-out/lib/libdanzig_gain.dylib`: Gain plugin (shared)

## Build Configuration

Danzig integrates with the azazel build system using CUE configuration:

**project.cue:**
```cue
danzig: #Module & {
    kind: "static"
    root: "src/danzig/root.zig"
}

danzig_gain: #Module & {
    kind: "shared"
    root: "examples/danzig-gain/root.zig"
    deps: ["danzig"]
}
```

**export.cue:**
```cue
_modules: {
    "danzig": danzig
    "danzig_gain": danzig_gain
}
```

## Creating Your Own Plugin

1. **Create Plugin Directory**
```bash
mkdir -p examples/my-plugin
```

2. **Implement Plugin Logic**
```zig
const danzig = @import("danzig");

pub const MyPlugin = struct {
    plugin: danzig.Plugin,
    
    pub fn init(allocator: std.mem.Allocator) !*MyPlugin {
        const self = try allocator.create(MyPlugin);
        self.plugin = danzig.Plugin.init(allocator);
        
        // Add parameters
        try self.plugin.addParameter(/* ... */);
        return self;
    }
    
    pub fn process(self: *MyPlugin, inputs: []*[*]f32, outputs: []*[*]f32, numChannels: u32, numSamples: u32) void {
        // Your DSP code here
    }
};
```

3. **Add to Build Config**
```cue
my_plugin: #Module & {
    kind: "shared"
    root: "examples/my-plugin/root.zig"
    deps: ["danzig"]
}
```

4. **Update export.cue**
```cue
_modules: {
    "my_plugin": my_plugin
}
```

5. **Build**
```bash
zig build
```

## Zig Version Requirements

- **Zig 0.14.0** or later

## VST3 Compliance

Danzig provides the essential VST3 C ABI bindings needed for:
- Plugin instantiation and factory functions
- Audio processing callbacks
- Parameter query and manipulation
- State management (save/load)
- MIDI and event handling (via ProcessData)

For full VST3 compliance, implement the factory functions and properly handle the C++ mangling or wrap with C++ glue code as needed by your host.

## Performance Characteristics

- **Minimal Overhead**: Direct mapping to VST3 C ABI
- **Zero-Copy Audio**: Audio buffers passed directly to DSP
- **Efficient Parameters**: Hash-map based parameter storage
- **No Runtime GC**: Uses Zig's allocator system

## Future Enhancements

Potential extensions to the Danzig framework:
- MIDI event handling abstractions
- Parameter change listener pattern
- Preset save/load system
- SIMD DSP utilities
- Template plugins (filter, EQ, compressor)

## License

Built as part of the Azazel build system ecosystem. See root repository for licensing.

## References

- [VST3 Specification](https://steinbergmedia.github.io/vst3_dev_portal/)
- [Zig Language](https://ziglang.org/)
- [Azazel Build System](/)
