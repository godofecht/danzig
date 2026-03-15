# Danzig VST3 Plugin Framework - Complete Documentation

**Table of Contents**
1. [Overview](#overview)
2. [Installation & Setup](#installation--setup)
3. [Quick Start](#quick-start)
4. [Core Concepts](#core-concepts)
5. [API Reference](#api-reference)
6. [Plugin Development Guide](#plugin-development-guide)
7. [Audio Processing](#audio-processing)
8. [Parameter System](#parameter-system)
9. [Build & Deployment](#build--deployment)
10. [Advanced Topics](#advanced-topics)
11. [Examples](#examples)
12. [Troubleshooting](#troubleshooting)

---

## Overview

Danzig is a **zero-dependency VST3 plugin development framework** written entirely in Zig. It provides type-safe abstractions for creating audio plugins without external dependencies, using only the Zig standard library.

### Design Philosophy

- **Minimal**: Only essential abstractions, no bloat
- **Modern**: Leverages Zig's memory safety and type system
- **Fast**: Direct VST3 C ABI, zero overhead
- **Educational**: Clear, understandable code for learning VST3

### Ecosystem

Built on the Azazel build system with CUE-based configuration for reproducible, modular builds.

---

## Installation & Setup

### Prerequisites

1. **Zig 0.14.0 or later**
   ```bash
   # macOS (using Homebrew)
   brew install zig
   
   # Or download from https://ziglang.org
   ```

2. **CUE (optional, for build configuration)**
   ```bash
   brew install cue
   ```

3. **Git** (to clone the repository)

### Getting Danzig

```bash
cd /Users/abhishekshivakumar/vex_zig/azazel
git status  # Verify you're in the repo
```

The danzig framework is already integrated into this azazel project!

### Verify Installation

```bash
zig build
./zig-out/bin/danzig_test
```

Expected output:
```
✓ Test executable compiles and links with danzig library
✓ Allocator initialized
✓ Danzig library linking successful!
```

---

## Quick Start

### Building the Framework

```bash
cd /Users/abhishekshivakumar/vex_zig/azazel

# Build all targets
zig build

# Or build specific module
zig build danzig_gain

# Clean build
rm -rf zig-cache && zig build
```

### Your First Plugin in 10 Minutes

#### Step 1: Create Plugin Directory
```bash
mkdir -p examples/my-first-plugin
```

#### Step 2: Write Plugin Code
Create `examples/my-first-plugin/root.zig`:

```zig
const std = @import("std");
const danzig = @import("danzig");

pub const MyPlugin = struct {
    plugin: danzig.Plugin,

    pub fn init(allocator: std.mem.Allocator) !*MyPlugin {
        const self = try allocator.create(MyPlugin);
        self.plugin = danzig.Plugin.init(allocator);
        
        // Add a simple parameter
        var param = danzig.Parameter{
            .id = 0,
            .normalized = 0.5,
            .plain = 0.0,
            .minValue = -100.0,
            .maxValue = 100.0,
            .defaultValue = 0.0,
        };
        @memcpy(param.title[0..9], "My Param\x00");
        try self.plugin.addParameter(param);
        
        return self;
    }

    pub fn process(self: *MyPlugin, inputs: []*[*]f32, outputs: []*[*]f32, channels: u32, samples: u32) void {
        // Simple pass-through for now
        for (0..channels) |ch| {
            @memcpy(outputs[ch][0..samples], inputs[ch][0..samples]);
        }
    }
};

pub fn main() !void {
    std.debug.print("My Plugin - ready to build!\n", .{});
}
```

#### Step 3: Add to Build Configuration

Edit `project.cue`:
```cue
my_first_plugin: #Module & {
	kind: "shared"
	root: "examples/my-first-plugin/root.zig"
	deps: ["danzig"]
}
```

Edit `export.cue`:
```cue
_modules: {
	"my_first_plugin": my_first_plugin
}
```

#### Step 4: Build
```bash
bash gen_build_spec.sh
zig build
```

Your plugin is at: `zig-out/lib/libmy_first_plugin.dylib`

---

## Core Concepts

### 1. Plugin Architecture

Every Danzig plugin consists of:

```
┌─────────────────────────────────────┐
│      VST3 Host (DAW)                │
└────────────┬────────────────────────┘
             │ VST3 API (C ABI)
┌────────────▼────────────────────────┐
│   VST3 Factory Interface            │
│   ├─ createInstance()               │
│   └─ getFactory()                   │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│   IComponent (Processor)            │
│   ├─ getBusCount()                  │
│   ├─ getParameterCount()            │
│   ├─ setState()                     │
│   └─ getState()                     │
└────────────┬────────────────────────┘
             │
┌────────────▼────────────────────────┐
│   IAudioProcessor (This is you!)    │
│   ├─ process()      ← Audio in/out  │
│   ├─ activate()     ← Start DSP     │
│   └─ deactivate()   ← Stop DSP      │
└─────────────────────────────────────┘
```

### 2. Plugin Lifecycle

```zig
// 1. Instantiation
var plugin = danzig.Plugin.init(allocator);

// 2. Configuration
plugin.setupProcessing(sampleRate, blockSize);
try plugin.addParameter(param);

// 3. Activation
plugin.activate();

// 4. Processing (called repeatedly by host)
plugin.process(inputs, outputs, channels, numSamples);

// 5. Deactivation
plugin.deactivate();

// 6. Cleanup
plugin.deinit();
```

### 3. The Allocator Pattern

Danzig uses Zig's allocator pattern for memory management:

```zig
// Create a general-purpose allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Pass to Danzig
var plugin = danzig.Plugin.init(allocator);
```

This gives you:
- **Explicit memory management** - no hidden allocations
- **Safety** - detects leaks and use-after-free
- **Control** - know exactly where memory is allocated

### 4. Parameter Concept

Parameters are the "knobs" on your plugin:

```zig
// Definition
pub const Parameter = struct {
    id: u32,                    // Unique identifier
    normalized: f64,            // 0.0 to 1.0 (from host)
    plain: f64,                 // Actual value (your code)
    title: [128]u8,             // Display name
    units: [64]u8,              // Unit label ("dB", "Hz", etc)
    minValue: f64,              // Minimum plain value
    maxValue: f64,              // Maximum plain value
    defaultValue: f64,          // Initial value
    stepCount: i32,             // 0 = continuous, >0 = stepped
};
```

Normalization converts between 0.0-1.0 range and actual values:

```zig
// Host sends normalized values (0.0-1.0)
plugin.setParameterNormalized(paramId, 0.75);

// You work with plain values
let gain_db = danzig.denormalize(0.75, -48.0, 48.0);  // Result: 12.0 dB
```

---

## API Reference

### Plugin Class

#### `Plugin.init(allocator: Allocator) Plugin`

Initialize a plugin instance.

```zig
var plugin = danzig.Plugin.init(allocator);
```

#### `Plugin.deinit(self: *Plugin) void`

Clean up plugin resources.

```zig
defer plugin.deinit();
```

#### `Plugin.addParameter(self: *Plugin, param: Parameter) !void`

Add a parameter to the plugin.

```zig
try plugin.addParameter(.{
    .id = 0,
    .minValue = -48.0,
    .maxValue = 48.0,
    .defaultValue = 0.0,
});
```

#### `Plugin.getParameterCount(self: Plugin) u32`

Get total number of parameters.

```zig
const count = plugin.getParameterCount();
```

#### `Plugin.setParameterNormalized(self: *Plugin, id: u32, value: f64) void`

Set parameter from normalized value (0.0-1.0).

```zig
plugin.setParameterNormalized(0, 0.5);  // Set to middle
```

#### `Plugin.getParameterNormalized(self: Plugin, id: u32) f64`

Get normalized parameter value.

```zig
const normalized = plugin.getParameterNormalized(0);
```

#### `Plugin.setupProcessing(self: *Plugin, sampleRate: f64, maxSamplesPerBlock: u32) void`

Configure for audio processing.

```zig
plugin.setupProcessing(44100.0, 256);  // 44.1 kHz, 256 sample blocks
```

#### `Plugin.activate(self: *Plugin) void`

Start processing audio. Called when plugin is inserted or DAW starts playback.

```zig
plugin.activate();  // Now ready for process() calls
```

#### `Plugin.deactivate(self: *Plugin) void`

Stop processing. Clean up any DSP state.

```zig
plugin.deactivate();
```

#### `Plugin.process(self: *Plugin, inputs: []*[*]f32, outputs: []*[*]f32, channels: u32, samples: u32) void`

Process audio block. This is called repeatedly by the host.

```zig
plugin.process(inputs, outputs, 2, 256);  // 2 channels, 256 samples
```

### Parameter Utilities

#### `normalize(plain: f64, min: f64, max: f64) f64`

Convert plain value to normalized (0.0-1.0).

```zig
const normalized = danzig.normalize(50.0, 0.0, 100.0);  // Result: 0.5
```

#### `denormalize(normalized: f64, min: f64, max: f64) f64`

Convert normalized value to plain.

```zig
const plain = danzig.denormalize(0.75, -48.0, 48.0);  // Result: 12.0
```

### Audio Processing

#### `GainProcessor`

Apply smooth gain changes.

```zig
pub const GainProcessor = struct {
    gain: f32,          // Current gain (linear)
    targetGain: f32,    // Target gain (linear)
    
    pub fn setGain(self: *GainProcessor, gainDb: f32) void
    pub fn process(self: *GainProcessor, inputs: []*[*]f32, outputs: []*[*]f32, channels: u32, samples: u32) void
    pub fn getNormalizedGain(self: GainProcessor) f32
    pub fn setNormalizedGain(self: *GainProcessor, normalized: f32) void
};
```

Example:
```zig
var gainProc = danzig.GainProcessor{};
gainProc.setGain(-6.0);  // -6 dB
gainProc.process(inputs, outputs, 2, 256);
```

#### `SimpleRamp`

Smooth parameter ramping over samples.

```zig
var ramp = danzig.SimpleRamp.init(0.0, 44100);  // Initial value, ramp samples
ramp.setTarget(1.0);  // Ramp to 1.0 over 44100 samples
for (0..44100) |_| {
    let value = ramp.next();
}
```

#### `AudioBuffer`

Multi-channel audio buffer with memory management.

```zig
var buf = try danzig.AudioBuffer.init(allocator, 2, 256, 44100.0);
defer buf.deinit(allocator);

buf.silence();  // Clear to zero
buf.clear();    // Same as silence
```

### Math Utilities

#### `linearInterpolate(x0: f32, x1: f32, t: f32) f32`

Linear interpolation between two values.

```zig
const value = danzig.linearInterpolate(0.0, 1.0, 0.5);  // Result: 0.5
```

#### `clamp(value: f32, min: f32, max: f32) f32`

Constrain value to range.

```zig
const clamped = danzig.clamp(1.5, 0.0, 1.0);  // Result: 1.0
```

#### `dBToLinear(dB: f32) f32`

Convert dB to linear gain.

```zig
const linear = danzig.dBToLinear(-6.0);  // Result: ~0.501
```

#### `linearTodB(linear: f32) f32`

Convert linear gain to dB.

```zig
const db = danzig.linearTodB(0.5);  // Result: ~-6.02 dB
```

---

## Plugin Development Guide

### Full Example: EQ Filter Plugin

Here's a complete 3-band parametric EQ example:

```zig
const std = @import("std");
const danzig = @import("danzig");

const ParamID = struct {
    pub const LowGain: u32 = 0;
    pub const MidGain: u32 = 1;
    pub const HighGain: u32 = 2;
};

pub const EQPlugin = struct {
    plugin: danzig.Plugin,
    lowGain: f32 = 1.0,
    midGain: f32 = 1.0,
    highGain: f32 = 1.0,

    pub fn init(allocator: std.mem.Allocator) !*EQPlugin {
        const self = try allocator.create(EQPlugin);
        self.plugin = danzig.Plugin.init(allocator);

        // Low band
        var lowParam = danzig.Parameter{
            .id = ParamID.LowGain,
            .normalized = 0.5,
            .minValue = -12.0,
            .maxValue = 12.0,
            .defaultValue = 0.0,
        };
        @memcpy(lowParam.title[0..7], "Low EQ\x00");
        @memcpy(lowParam.units[0..2], "dB");
        try self.plugin.addParameter(lowParam);

        // Mid band
        var midParam = danzig.Parameter{
            .id = ParamID.MidGain,
            .normalized = 0.5,
            .minValue = -12.0,
            .maxValue = 12.0,
            .defaultValue = 0.0,
        };
        @memcpy(midParam.title[0..7], "Mid EQ\x00");
        try self.plugin.addParameter(midParam);

        // High band
        var highParam = danzig.Parameter{
            .id = ParamID.HighGain,
            .normalized = 0.5,
            .minValue = -12.0,
            .maxValue = 12.0,
            .defaultValue = 0.0,
        };
        @memcpy(highParam.title[0..8], "High EQ\x00");
        try self.plugin.addParameter(highParam);

        return self;
    }

    pub fn deinit(self: *EQPlugin, allocator: std.mem.Allocator) void {
        self.plugin.deinit();
        allocator.destroy(self);
    }

    pub fn setParameterNormalized(self: *EQPlugin, paramId: u32, normalized: f64) void {
        self.plugin.setParameterNormalized(paramId, normalized);
        const db = danzig.denormalize(normalized, -12.0, 12.0);
        
        switch (paramId) {
            ParamID.LowGain => self.lowGain = danzig.dBToLinear(@floatCast(db)),
            ParamID.MidGain => self.midGain = danzig.dBToLinear(@floatCast(db)),
            ParamID.HighGain => self.highGain = danzig.dBToLinear(@floatCast(db)),
            else => {},
        }
    }

    pub fn process(self: *EQPlugin, inputs: []*[*]f32, outputs: []*[*]f32, channels: u32, samples: u32) void {
        // Simple gain-based "EQ" (real implementation would use filters)
        for (0..channels) |ch| {
            for (0..samples) |s| {
                var sample = inputs[ch][s];
                // Apply gains (this is simplified - real EQ uses filters)
                sample *= (self.lowGain + self.midGain + self.highGain) / 3.0;
                outputs[ch][s] = danzig.clamp(sample, -1.0, 1.0);
            }
        }
    }
};

pub fn main() !void {
    std.debug.print("3-Band EQ Plugin\n", .{});
}
```

### Step-by-Step Development Workflow

#### 1. **Design Phase**
   - Define parameters (knobs/controls)
   - Sketch audio algorithm
   - Plan DSP implementation

#### 2. **Implementation Phase**
   ```zig
   pub const MyPlugin = struct {
       plugin: danzig.Plugin,
       // Your state variables
       
       pub fn init(allocator) !*MyPlugin { ... }
       pub fn process(...) void { ... }
   };
   ```

#### 3. **Parameter Setup**
   ```zig
   try self.plugin.addParameter(.{
       .id = 0,
       .minValue = min,
       .maxValue = max,
       .defaultValue = default,
   });
   ```

#### 4. **Audio Processing**
   ```zig
   pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) {
       for (0..channels) |ch| {
           for (0..samples) |s| {
               outputs[ch][s] = self.dsp(inputs[ch][s]);
           }
       }
   }
   ```

#### 5. **Testing**
   - Add to build config
   - Build: `zig build`
   - Test in DAW
   - Debug with debug symbols

---

## Audio Processing

### Signal Flow

```
Host Buffer (interleaved or deinterleaved)
    ↓
Your plugin.process()
    ├─ Read from inputs[]
    ├─ Apply DSP
    └─ Write to outputs[]
    ↓
Host Buffer
```

### Buffer Format

Danzig uses **deinterleaved floating-point** audio:

```zig
// inputs and outputs are arrays of pointers
// inputs[0] → left channel samples
// inputs[1] → right channel samples
// inputs[0][0..numSamples] → all left channel samples

for (0..numChannels) |ch| {
    for (0..numSamples) |s| {
        let sample = inputs[ch][s];    // Read
        outputs[ch][s] = process(sample);  // Write
    }
}
```

### Common DSP Patterns

#### Simple Gain
```zig
for (0..numChannels) |ch| {
    for (0..numSamples) |s| {
        outputs[ch][s] = inputs[ch][s] * gainAmount;
    }
}
```

#### Soft Clipping
```zig
const in = inputs[ch][s];
const out = std.math.tanh(in * driveAmount);
outputs[ch][s] = out;
```

#### Delay Buffer
```zig
pub const DelayPlugin = struct {
    plugin: danzig.Plugin,
    delayBuffer: [*]f32,
    delayTime: f32,
    writePos: u32 = 0,

    pub fn process(self: *DelayPlugin, inputs, outputs, channels, samples) {
        for (0..channels) |ch| {
            for (0..samples) |s| {
                // Read from delay
                let readPos = (self.writePos -| @intFromFloat(self.delayTime)) % BUFFER_SIZE;
                let delayed = self.delayBuffer[readPos];
                
                // Write to output (mix)
                outputs[ch][s] = (inputs[ch][s] + delayed) * 0.5;
                
                // Write to delay buffer
                self.delayBuffer[self.writePos] = inputs[ch][s];
                self.writePos = (self.writePos + 1) % BUFFER_SIZE;
            }
        }
    }
};
```

---

## Parameter System

### Parameter Types

#### Continuous Parameters
```zig
var gainParam = danzig.Parameter{
    .id = 0,
    .minValue = -48.0,
    .maxValue = 12.0,
    .stepCount = 0,  // 0 = continuous
};
```

#### Stepped/Discrete Parameters
```zig
var modeParam = danzig.Parameter{
    .id = 1,
    .minValue = 0.0,
    .maxValue = 3.0,
    .stepCount = 3,  // Discrete steps
};
```

#### Boolean/Bypass
```zig
var bypassParam = danzig.Parameter{
    .id = 2,
    .minValue = 0.0,
    .maxValue = 1.0,
    .stepCount = 1,  // Only 0 or 1
};
```

### Parameter Handling

```zig
pub fn setParameterNormalized(self: *MyPlugin, paramId: u32, normalized: f64) void {
    self.plugin.setParameterNormalized(paramId, normalized);
    
    switch (paramId) {
        0 => {  // Gain
            const db = danzig.denormalize(normalized, -48.0, 12.0);
            self.gain = danzig.dBToLinear(@floatCast(db));
        },
        1 => {  // Mode
            const mode = @as(u32, @intFromFloat(danzig.denormalize(normalized, 0.0, 3.0)));
            self.mode = mode;
        },
        else => {},
    }
}
```

---

## Build & Deployment

### Build Configuration

#### project.cue
```cue
my_plugin: #Module & {
    kind: "shared"           // Produces .dylib/.so/.dll
    root: "examples/my-plugin/root.zig"
    deps: ["danzig"]         // Depends on danzig library
}
```

#### export.cue
```cue
_modules: {
    "my_plugin": my_plugin
}
```

### Building

```bash
# Regenerate build spec from CUE
bash gen_build_spec.sh

# Build all
zig build

# Build specific module
zig build my_plugin

# Build with optimization
zig build -DReleaseFast
```

### Output Locations

```
zig-out/
├── lib/
│   ├── libdanzig.a              # Library
│   └── libmy_plugin.dylib       # Your plugin (macOS)
└── bin/
    └── executable_targets/
```

### Deployment

#### macOS VST3 Bundle Structure
```
MyPlugin.vst3/
└── Contents/
    ├── Info.plist
    └── MacOS/
        └── libmy_plugin.dylib
```

#### Create VST3 Bundle
```bash
mkdir -p MyPlugin.vst3/Contents/MacOS
cp zig-out/lib/libmy_plugin.dylib MyPlugin.vst3/Contents/MacOS/
cp path/to/Info.plist MyPlugin.vst3/Contents/
```

---

## Advanced Topics

### Custom Memory Allocation

```zig
// Use Arena allocator for temporary data
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

const temp_allocator = arena.allocator();
var temp_data = try temp_allocator.alloc(f32, 1024);
```

### SIMD Optimization

```zig
// Zig supports manual SIMD
const vec4 = @Vector(4, f32);

var simd_gains = @as(vec4, @splat(self.gain));
var simd_samples: vec4 = .{ in[0], in[1], in[2], in[3] };
var simd_result = simd_samples * simd_gains;
```

### Error Handling

```zig
pub fn addParameter(self: *Plugin, param: Parameter) !void {
    try self.parameters.add(param);  // Propagate errors
}

pub fn process(...) !void {  // Can return errors
    // Allocations
}
```

### Multi-threading Considerations

Danzig plugins run on the **audio thread** (real-time):
- No allocations during `process()`
- Pre-allocate all buffers in `setupProcessing()`
- Use atomic operations for lock-free communication with UI thread

```zig
// Good: Allocate once
pub fn setupProcessing(...) {
    self.buffer = allocator.alloc(...);  // OK
}

// Bad: Don't allocate in process!
pub fn process(...) {
    const temp = try allocator.alloc(...);  // WRONG!
}
```

---

## Examples

### Mixer/Gain Plugin
```zig
pub const GainPlugin = struct {
    plugin: danzig.Plugin,
    gains: [8]f32 = [_]f32{1.0} ** 8,

    pub fn process(self: *GainPlugin, inputs, outputs, channels, samples) {
        for (0..channels) |ch| {
            for (0..samples) |s| {
                outputs[ch][s] = inputs[ch][s] * self.gains[ch];
            }
        }
    }
};
```

### Compressor Skeleton
```zig
pub const CompressorPlugin = struct {
    plugin: danzig.Plugin,
    threshold: f32,
    ratio: f32,
    attackTime: f32,
    releaseTime: f32,
    envelope: f32 = 0.0,

    pub fn process(self: *CompressorPlugin, inputs, outputs, channels, samples) {
        for (0..samples) |s| {
            // Detect peak
            var peak: f32 = 0.0;
            for (0..channels) |ch| {
                peak = @max(peak, @abs(inputs[ch][s]));
            }

            // Attack/Release envelope
            if (peak > self.envelope) {
                self.envelope += (peak - self.envelope) * self.attackTime;
            } else {
                self.envelope -= (self.envelope - peak) * self.releaseTime;
            }

            // Calculate gain reduction
            var gainReduction: f32 = 1.0;
            if (self.envelope > self.threshold) {
                gainReduction = 1.0 / (1.0 + (self.envelope / self.threshold - 1.0) * (self.ratio - 1.0));
            }

            // Apply
            for (0..channels) |ch| {
                outputs[ch][s] = inputs[ch][s] * gainReduction;
            }
        }
    }
};
```

### Reverb (Simplified)
```zig
pub const ReverbPlugin = struct {
    plugin: danzig.Plugin,
    buffers: [4][*]f32,
    positions: [4]u32 = [_]u32{0} ** 4,
    mix: f32 = 0.5,

    pub fn process(self: *ReverbPlugin, inputs, outputs, channels, samples) {
        const delay_sizes = [_]u32{ 12345, 23456, 34567, 45678 };

        for (0..samples) |s| {
            var delayed: f32 = 0.0;

            for (0..4) |buf| {
                delayed += self.buffers[buf][self.positions[buf]];
                self.buffers[buf][self.positions[buf]] = inputs[0][s];
                self.positions[buf] = (self.positions[buf] + 1) % delay_sizes[buf];
            }

            for (0..channels) |ch| {
                outputs[ch][s] = danzig.linearInterpolate(inputs[ch][s], delayed * 0.25, self.mix);
            }
        }
    }
};
```

---

## Troubleshooting

### Build Issues

**Error: "no module named 'danzig'"**
- Make sure `deps: ["danzig"]` is in `project.cue`
- Verify `"danzig": danzig` is in `export.cue`
- Run `bash gen_build_spec.sh`

**Compilation errors**
- Check Zig version: `zig version` (need 0.14.0+)
- Look for unused parameters/variables (Zig is strict)
- Use `_` to ignore unused values: `pub fn foo(_: u32) {}`

**Linking errors**
- Verify plugin depends on danzig: `deps: ["danzig"]`
- Check that danzig module is built first
- Ensure output paths are correct

### Runtime Issues

**Plugin crashes on activate**
- Don't allocate in `activate()`, do it in `setupProcessing()`
- Check allocator isn't null
- Verify buffer sizes

**Audio distorts**
- Check clipping: use `danzig.clamp(value, -1.0, 1.0)`
- Monitor gain levels
- Avoid NaN/Inf values

**Parameter changes don't work**
- Verify parameter ID is correct
- Check normalization range (should be 0.0-1.0)
- Ensure `setParameterNormalized` is called from host

**Plugin not recognized by DAW**
- Check VST3 bundle structure
- Verify `_GetPluginFactory` exports: `nm zig-out/lib/libmy_plugin.dylib | grep GetPluginFactory`
- Try loading in VST validator tool

### Performance

**Clicks/pops in audio**
- Reduce allocations (pre-allocate buffers)
- Use fast math (avoid expensive ops in audio loop)
- Profile with profiler

**High CPU usage**
- Optimize DSP (use SIMD, avoid expensive functions)
- Reduce parameter smoothing resolution
- Cache computed values

---

## Best Practices

### Memory
✓ Use allocators, not raw malloc
✓ Pre-allocate in `setupProcessing()`, not `process()`
✓ Use `defer` for cleanup
✗ Don't leak memory in errors

### Audio
✓ Clamp outputs to [-1.0, 1.0]
✓ Handle NaN/Inf gracefully
✓ Use ramps for parameter changes (no clicks)
✗ Don't trust input ranges

### Parameters
✓ Use meaningful IDs (0, 1, 2...)
✓ Provide default values
✓ Document value ranges
✗ Don't change parameter count after init

### Performance
✓ Keep audio processing simple/fast
✓ Use fixed-size allocations
✓ Profile real code
✗ Don't do expensive work in `process()`

---

## Resources

- **VST3 Specification**: https://steinbergmedia.github.io/vst3_dev_portal/
- **Zig Documentation**: https://ziglang.org/documentation/
- **Audio DSP**: https://www.dsprelated.com/
- **Danzig Source**: `src/danzig/` in this repository

---

## Support

For issues or questions:
1. Check this documentation
2. Review examples in `examples/danzig-gain/`
3. Look at source code in `src/danzig/`
4. Check build logs with `zig build` (verbose output)

---

**Last Updated**: 2026-03-15
**Danzig Version**: 1.0
**Zig Requirement**: 0.14.0+
