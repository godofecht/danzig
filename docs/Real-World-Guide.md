# Danzig Real-World Plugin Development Guide

Practical tips, common pitfalls, and complete working examples.

## Table of Contents

1. [Getting Started the Right Way](#getting-started-the-right-way)
2. [Common Pitfalls](#common-pitfalls)
3. [Real-World Examples](#real-world-examples)
4. [Performance Optimization](#performance-optimization)
5. [Testing Your Plugin](#testing-your-plugin)
6. [Debugging Techniques](#debugging-techniques)
7. [Multi-threaded Considerations](#multi-threaded-considerations)
8. [Distributing Your Plugin](#distributing-your-plugin)

---

## Getting Started the Right Way

### Checklist Before Coding

- [ ] Decide on plugin type (effect, generator, utility)
- [ ] Define all parameters (name, range, default)
- [ ] Plan your audio algorithm
- [ ] Know your target DAW(s)
- [ ] Design your UI (if needed)

### Project Template

Create a new plugin with this structure:

```bash
mkdir -p my-plugin/src
cd my-plugin

# Create build files
cat > project.cue << 'EOF'
my_plugin: #Module & {
    kind: "shared"
    root: "src/plugin.zig"
    deps: ["danzig"]
}
EOF

cat > export.cue << 'EOF'
_modules: {
    "my_plugin": my_plugin
}
EOF

# Create plugin skeleton
cat > src/plugin.zig << 'EOF'
const std = @import("std");
const danzig = @import("danzig");

pub const MyPlugin = struct {
    plugin: danzig.Plugin,
    
    pub fn init(allocator: std.mem.Allocator) !*MyPlugin {
        const self = try allocator.create(MyPlugin);
        self.plugin = danzig.Plugin.init(allocator);
        return self;
    }
    
    pub fn process(self: *MyPlugin, inputs: []*[*]f32, outputs: []*[*]f32, channels: u32, samples: u32) void {
        // TODO: Implement DSP
        for (0..channels) |ch| {
            @memcpy(outputs[ch][0..samples], inputs[ch][0..samples]);
        }
    }
};

pub fn main() void {
    std.debug.print("My Plugin\n", .{});
}
EOF
```

---

## Common Pitfalls

### Pitfall 1: Allocating in process()

**WRONG** ❌
```zig
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    var buffer = try self.allocator.alloc(f32, samples);  // DON'T!
    // This blocks the audio thread!
}
```

**RIGHT** ✅
```zig
pub const MyPlugin = struct {
    // Pre-allocate during setup
    buffer: []f32,
    
    pub fn setupProcessing(self: *MyPlugin, sampleRate: f64, maxBlockSize: u32) void {
        self.buffer = self.allocator.alloc(f32, maxBlockSize) catch unreachable;
    }
    
    pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
        // Use pre-allocated buffer
        for (0..samples) |i| {
            self.buffer[i] = inputs[0][i] * self.gain;
        }
    }
};
```

### Pitfall 2: Forgetting Reference Counting

**WRONG** ❌
```zig
// Host's reference count leaks
pub fn queryInterface(self: *anyopaque, iid, obj) i32 {
    obj.* = self;
    return 0;
    // Never increments ref count!
}
```

**RIGHT** ✅
```zig
pub fn queryInterface(self: *anyopaque, iid, obj) i32 {
    obj.* = self;
    addRef(self);  // Increment!
    return 0;
}
```

### Pitfall 3: Not Handling Edge Cases

**WRONG** ❌
```zig
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    // Assumes input is non-null
    let sample = inputs[0][0];
    let result = 1.0 / sample;  // Division by zero!
}
```

**RIGHT** ✅
```zig
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    for (0..samples) |s| {
        var sample = inputs[0][s];
        
        // Handle edge cases
        if (@abs(sample) < 0.0001) sample = 0.0;  // Denormal
        if (@isNan(sample)) sample = 0.0;         // NaN
        if (@isInfinite(sample)) sample = 0.0;    // Inf
        
        // Safe divide
        let divisor = std.math.clamp(sample, 0.0001, 1.0);
        let result = 1.0 / divisor;
        
        outputs[0][s] = danzig.clamp(result, -1.0, 1.0);
    }
}
```

### Pitfall 4: Parameter Feedback Loop

**WRONG** ❌
```zig
pub fn setParameterNormalized(self: *MyPlugin, id: u32, value: f64) void {
    self.plugin.setParameterNormalized(id, value);
    self.hostCallback.setValue(id, value);  // Host gets notified of change it just sent!
}
```

**RIGHT** ✅
```zig
pub fn setParameterNormalized(self: *MyPlugin, id: u32, value: f64) void {
    self.plugin.setParameterNormalized(id, value);
    // Don't notify host back - it already knows
}
```

### Pitfall 5: Not Handling Silence Flags

**WRONG** ❌
```zig
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    // Processes silence, wasting CPU
    let output = self.dsp(inputs[0][0]);
    for (0..samples) |s| {
        outputs[0][s] = output;
    }
}
```

**RIGHT** ✅
```zig
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    // Check silence flags (ProcessData.silenceFlags)
    if (inputs[0].silenceFlags != 0) {
        // Input is silent, skip processing
        return;
    }
    
    for (0..samples) |s| {
        outputs[0][s] = self.dsp(inputs[0][s]);
    }
}
```

---

## Real-World Examples

### Example 1: Simple Tremolo (LFO Modulation)

```zig
const std = @import("std");
const danzig = @import("danzig");

const PI = std.math.pi;

pub const TremoloPlugin = struct {
    plugin: danzig.Plugin,
    
    // Parameters
    rate: f32 = 5.0,      // Hz
    depth: f32 = 0.5,     // 0-1
    
    // State
    phase: f32 = 0.0,
    sampleRate: f64 = 44100.0,

    pub fn init(allocator: std.mem.Allocator) !*TremoloPlugin {
        const self = try allocator.create(TremoloPlugin);
        self.plugin = danzig.Plugin.init(allocator);

        // Add parameters
        var rateParam = danzig.Parameter{
            .id = 0,
            .normalized = 0.25,
            .minValue = 0.1,
            .maxValue = 20.0,
            .defaultValue = 5.0,
        };
        @memcpy(rateParam.title[0..4], "Rate");
        @memcpy(rateParam.units[0..2], "Hz");
        try self.plugin.addParameter(rateParam);

        var depthParam = danzig.Parameter{
            .id = 1,
            .normalized = 0.5,
            .minValue = 0.0,
            .maxValue = 1.0,
            .defaultValue = 0.5,
        };
        @memcpy(depthParam.title[0..5], "Depth");
        try self.plugin.addParameter(depthParam);

        return self;
    }

    pub fn deinit(self: *TremoloPlugin, allocator: std.mem.Allocator) void {
        self.plugin.deinit();
        allocator.destroy(self);
    }

    pub fn setupProcessing(self: *TremoloPlugin, sampleRate: f64, _: u32) void {
        self.plugin.setupProcessing(sampleRate, 256);
        self.sampleRate = sampleRate;
    }

    pub fn setParameterNormalized(self: *TremoloPlugin, id: u32, normalized: f64) void {
        self.plugin.setParameterNormalized(id, normalized);
        
        switch (id) {
            0 => {
                // Rate parameter
                self.rate = @floatCast(danzig.denormalize(normalized, 0.1, 20.0));
            },
            1 => {
                // Depth parameter
                self.depth = @floatCast(danzig.denormalize(normalized, 0.0, 1.0));
            },
            else => {},
        }
    }

    pub fn process(self: *TremoloPlugin, inputs: []*[*]f32, outputs: []*[*]f32, channels: u32, samples: u32) void {
        if (!self.plugin.active) {
            for (0..channels) |ch| {
                @memcpy(outputs[ch][0..samples], inputs[ch][0..samples]);
            }
            return;
        }

        let sampleDuration = 1.0 / self.sampleRate;
        
        for (0..samples) |s| {
            // Update phase
            self.phase += @as(f32, @floatCast(self.rate * sampleDuration));
            if (self.phase >= 1.0) self.phase -= 1.0;

            // Calculate LFO (sine wave)
            let lfo = @sin(self.phase * 2.0 * PI);
            let modulation = danzig.linearInterpolate(1.0, lfo, self.depth);

            // Apply tremolo to all channels
            for (0..channels) |ch| {
                outputs[ch][s] = inputs[ch][s] * modulation;
            }
        }
    }
};

pub fn main() void {
    std.debug.print("Tremolo Plugin\n", .{});
}
```

### Example 2: Soft Clipper with Smoothing

```zig
pub const SoftClipperPlugin = struct {
    plugin: danzig.Plugin,
    
    threshold: f32 = 0.8,
    driveAmount: f32 = 1.0,
    
    pub fn process(self: *SoftClipperPlugin, inputs, outputs, channels, samples) void {
        for (0..channels) |ch| {
            for (0..samples) |s| {
                var sample = inputs[ch][s] * self.driveAmount;
                
                // Soft clipping using tanh
                let clipped = @tanh(sample);
                
                // Smooth transition around threshold
                if (@abs(sample) > self.threshold) {
                    let ratio = self.threshold / @abs(sample);
                    sample = danzig.linearInterpolate(clipped, sample, ratio);
                }
                
                outputs[ch][s] = danzig.clamp(sample, -1.0, 1.0);
            }
        }
    }
};
```

### Example 3: Delay/Echo Plugin

```zig
const MAX_DELAY_SECONDS = 10.0;

pub const DelayPlugin = struct {
    plugin: danzig.Plugin,
    
    delayBuffer: [*]f32,
    delayTime: f32 = 0.5,      // seconds
    feedback: f32 = 0.5,       // 0-1
    mixAmount: f32 = 0.5,      // wet/dry
    writePos: u32 = 0,
    bufferSize: u32,
    sampleRate: f64 = 44100.0,

    pub fn init(allocator: std.mem.Allocator) !*DelayPlugin {
        const self = try allocator.create(DelayPlugin);
        self.plugin = danzig.Plugin.init(allocator);
        
        // Allocate delay buffer
        const maxSamples = @intFromFloat(MAX_DELAY_SECONDS * 44100.0);
        self.delayBuffer = try allocator.alloc(f32, maxSamples);
        self.bufferSize = maxSamples;
        
        @memset(self.delayBuffer[0..maxSamples], 0.0);
        
        return self;
    }

    pub fn process(self: *DelayPlugin, inputs, outputs, channels, samples) void {
        let delayReadPos = self.writePos -% @intFromFloat(self.delayTime * self.sampleRate);
        
        for (0..channels) |ch| {
            for (0..samples) |s| {
                // Read from delay
                let delayed = self.delayBuffer[delayReadPos % self.bufferSize];
                
                // Mix wet/dry
                let wet = delayed;
                let dry = inputs[ch][s];
                outputs[ch][s] = danzig.linearInterpolate(dry, wet, self.mixAmount);
                
                // Write to delay (with feedback)
                self.delayBuffer[self.writePos % self.bufferSize] = 
                    inputs[ch][s] + (delayed * self.feedback);
            }
        }
        
        self.writePos = (self.writePos + 1) % self.bufferSize;
    }
};
```

---

## Performance Optimization

### Profile First

```bash
# Compile with optimization
zig build -DReleaseFast

# Use system profiler on macOS
instruments -t "System Trace" ./plugin
```

### Common Bottlenecks

| Issue | Solution |
|-------|----------|
| Expensive math | Use approximations, precompute |
| Cache misses | Improve memory access patterns |
| Allocations | Pre-allocate everything |
| Function calls | Inline hot paths |
| Denormals | Flush to zero |

### SIMD Processing

```zig
const vec4 = @Vector(4, f32);

pub fn processVector(self: *MyPlugin, inputs: [*][*]f32, samples: u32) void {
    var i: u32 = 0;
    while (i + 4 <= samples) : (i += 4) {
        // Load 4 samples
        var v: vec4 = undefined;
        v[0] = inputs[0][i];
        v[1] = inputs[0][i + 1];
        v[2] = inputs[0][i + 2];
        v[3] = inputs[0][i + 3];
        
        // Apply gain to all 4 simultaneously
        var result = v * @as(vec4, @splat(self.gain));
        
        // Store back
        inputs[0][i] = result[0];
        inputs[0][i + 1] = result[1];
        inputs[0][i + 2] = result[2];
        inputs[0][i + 3] = result[3];
    }
    
    // Handle remaining samples
    while (i < samples) : (i += 1) {
        inputs[0][i] *= self.gain;
    }
}
```

### Denormal Handling

```zig
// Flush denormal floats to zero
pub fn flushDenormals(value: f32) f32 {
    if (@abs(value) < 1e-37) {
        return 0.0;
    }
    return value;
}

// Or use DAZ (Denormalized as Zero) in your DSP:
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    for (0..samples) |s| {
        var sample = flushDenormals(inputs[0][s]);
        sample = self.dsp(sample);
        outputs[0][s] = flushDenormals(sample);
    }
}
```

---

## Testing Your Plugin

### Unit Tests

```zig
test "tremolo rate parameter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var plugin = try TremoloPlugin.init(allocator);
    defer plugin.deinit(allocator);
    
    plugin.setParameterNormalized(0, 0.5);
    try std.testing.expect(@abs(plugin.rate - 10.25) < 0.1);
}

test "process produces output" {
    var plugin = try MyPlugin.init(allocator);
    defer plugin.deinit(allocator);
    
    plugin.setupProcessing(44100.0, 256);
    plugin.activate();
    
    var input = [_]f32{0.5} ** 256;
    var output = [_]f32{0.0} ** 256;
    
    var inputs = [_]*[*]f32{input.ptr};
    var outputs = [_]*[*]f32{output.ptr};
    
    plugin.process(&inputs, &outputs, 1, 256);
    
    // Verify output changed
    try std.testing.expect(output[0] != 0.0);
}
```

### Manual Testing in DAW

1. Build: `zig build`
2. Create VST3 bundle:
   ```bash
   mkdir -p MyPlugin.vst3/Contents/MacOS
   cp zig-out/lib/libmy_plugin.dylib MyPlugin.vst3/Contents/MacOS/
   ```
3. Copy to DAW plugin folder:
   ```bash
   cp -r MyPlugin.vst3 ~/Library/Audio/Plug-ins/VST3/
   ```
4. Open DAW, scan plugins, test

---

## Debugging Techniques

### Logging

```zig
pub fn debugLog(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[Plugin] " ++ fmt ++ "\n", args);
}

pub fn process(...) void {
    debugLog("Processing {} samples", .{samples});
    for (0..samples) |s| {
        let value = inputs[0][s];
        if (@abs(value) > 1.0) {
            debugLog("Clipping at sample {}: {}", .{s, value});
        }
    }
}
```

### Assertions

```zig
pub fn process(...) void {
    std.debug.assert(channels > 0);
    std.debug.assert(samples > 0);
    std.debug.assert(inputs.len == channels);
    std.debug.assert(outputs.len == channels);
    
    // Safe to process
}
```

### Null Checks

```zig
pub fn process(self: *MyPlugin, inputs, outputs, channels, samples) void {
    if (inputs == null or outputs == null) {
        std.debug.print("ERROR: null buffer pointers\n", .{});
        return;
    }
}
```

---

## Multi-threaded Considerations

### Audio Thread vs. UI Thread

```zig
pub const MyPlugin = struct {
    // Audio thread data (accessed in process())
    gain: std.atomic.Value(f32) = std.atomic.Value(f32).init(1.0),
    
    // UI thread data
    ui_state: mutex-protected data,
    
    pub fn process(self: *MyPlugin, ...) void {
        // Safe: atomic read on audio thread
        let gain = self.gain.load(.SeqCst);
        
        for (0..samples) |s| {
            outputs[0][s] = inputs[0][s] * gain;
        }
    }
    
    pub fn setParameterNormalized(self: *MyPlugin, id, value) void {
        // Can be called from UI thread
        // Use atomic operations for audio-thread-safe updates
        let new_gain = denormalize(value, 0.0, 2.0);
        self.gain.store(@floatCast(new_gain), .SeqCst);
    }
};
```

### Lock-Free Communication

```zig
pub const RingBuffer = struct {
    buffer: [*]f32,
    write_pos: std.atomic.Value(u32),
    read_pos: std.atomic.Value(u32),
    size: u32,
    
    pub fn write(self: *RingBuffer, value: f32) bool {
        let w = self.write_pos.load(.SeqCst);
        let r = self.read_pos.load(.SeqCst);
        
        let next_w = (w + 1) % self.size;
        if (next_w == r) return false;  // Buffer full
        
        self.buffer[w] = value;
        self.write_pos.store(next_w, .SeqCst);
        return true;
    }
    
    pub fn read(self: *RingBuffer) ?f32 {
        let r = self.read_pos.load(.SeqCst);
        let w = self.write_pos.load(.SeqCst);
        
        if (r == w) return null;  // Buffer empty
        
        let value = self.buffer[r];
        self.read_pos.store((r + 1) % self.size, .SeqCst);
        return value;
    }
};
```

---

## Distributing Your Plugin

### Checklist

- [ ] Code compiles without warnings
- [ ] All parameters documented
- [ ] Audio processing tested
- [ ] No memory leaks (checked with valgrind/instruments)
- [ ] Works in major DAWs
- [ ] Has proper plugin info/version
- [ ] User-friendly parameter names

### macOS VST3 Bundle

```bash
PLUGIN_NAME=MyGainPlugin
BUNDLE_NAME=${PLUGIN_NAME}.vst3

mkdir -p ${BUNDLE_NAME}/Contents/MacOS
mkdir -p ${BUNDLE_NAME}/Contents/Resources

# Copy binary
cp zig-out/lib/lib${PLUGIN_NAME}.dylib ${BUNDLE_NAME}/Contents/MacOS/${PLUGIN_NAME}

# Create Info.plist
cat > ${BUNDLE_NAME}/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MyGainPlugin</string>
    <key>CFBundleIdentifier</key>
    <string>com.mycompany.MyGainPlugin</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>My Gain Plugin</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
EOF

# Optional: Code sign
codesign -s - ${BUNDLE_NAME}
```

### Distribution

```bash
# Create archive
zip -r MyGainPlugin-1.0.0-macOS.zip ${BUNDLE_NAME}

# Verify
unzip -t MyGainPlugin-1.0.0-macOS.zip
```

---

## Resources

- **Official VST3 SDK**: https://github.com/steinbergmedia/vst3sdk
- **VST3 Plugin Examples**: https://github.com/steinbergmedia/vst3_c_api
- **Audio DSP Learning**: https://www.dsprelated.com/
- **Zig Documentation**: https://ziglang.org/documentation/
- **Superelectric VST3+Zig Post**: https://superelectric.dev/post/post1.html
