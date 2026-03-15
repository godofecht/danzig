# Danzig Documentation Index

Complete documentation for the Danzig VST3 plugin framework in Zig.

## Quick Navigation

### 🚀 Getting Started
- **[Danzig Complete Guide](./Danzig-Complete-Guide.md)** - Full API reference, quickstart, and examples
- **[Real-World Guide](./Real-World-Guide.md)** - Practical development, pitfalls, and complete examples

### 🏗️ Architecture & Design
- **[VST3 Architecture](./VST3-Architecture.md)** - Deep dive into VST3, COM, and how Danzig abstracts them

### 📚 Documentation By Topic

#### Installation & Setup
- Start here: [Installation & Setup](./Danzig-Complete-Guide.md#installation--setup)
- Verify installation: [Verify Installation](./Danzig-Complete-Guide.md#verify-installation)

#### Quick Start
- 10-minute tutorial: [Quick Start](./Danzig-Complete-Guide.md#quick-start)
- Your first plugin: [Your First Plugin in 10 Minutes](./Danzig-Complete-Guide.md#your-first-plugin-in-10-minutes)

#### Core Concepts
- [Plugin Architecture](./Danzig-Complete-Guide.md#plugin-architecture)
- [Plugin Lifecycle](./Danzig-Complete-Guide.md#plugin-lifecycle)
- [The Allocator Pattern](./Danzig-Complete-Guide.md#the-allocator-pattern)
- [Parameters](./Danzig-Complete-Guide.md#parameter-concept)

#### API Reference
- Complete API docs: [API Reference](./Danzig-Complete-Guide.md#api-reference)
- Plugin class: [Plugin Class](./Danzig-Complete-Guide.md#plugin-class)
- Parameters: [Parameter System](./Danzig-Complete-Guide.md#parameter-system)
- Audio processing: [Audio Processing](./Danzig-Complete-Guide.md#audio-processing)

#### Plugin Development
- Full guide: [Plugin Development Guide](./Danzig-Complete-Guide.md#plugin-development-guide)
- Audio processing patterns: [Audio Processing](./Danzig-Complete-Guide.md#audio-processing)
- Parameter handling: [Parameter System](./Danzig-Complete-Guide.md#parameter-system)
- Build & deployment: [Build & Deployment](./Danzig-Complete-Guide.md#build--deployment)

#### Advanced Topics
- [Advanced Topics](./Danzig-Complete-Guide.md#advanced-topics)
- Memory allocation strategies
- SIMD optimization
- Error handling
- Multi-threading

#### Real-World Development
- Project setup: [Getting Started the Right Way](./Real-World-Guide.md#getting-started-the-right-way)
- Common pitfalls: [Common Pitfalls](./Real-World-Guide.md#common-pitfalls)
- Working examples: [Real-World Examples](./Real-World-Guide.md#real-world-examples)
- Performance: [Performance Optimization](./Real-World-Guide.md#performance-optimization)
- Testing: [Testing Your Plugin](./Real-World-Guide.md#testing-your-plugin)
- Debugging: [Debugging Techniques](./Real-World-Guide.md#debugging-techniques)

#### VST3 Deep Dive
- [VST3 vs Other Formats](./VST3-Architecture.md#vst3-vs-other-plugin-formats)
- [COM/VST-MA Fundamentals](./VST3-Architecture.md#comvst-ma-fundamentals)
- [GUIDs and Interface IDs](./VST3-Architecture.md#guids-and-interface-ids)
- [Virtual Tables (VTables)](./VST3-Architecture.md#virtual-tables-vtables)
- [The IUnknown Pattern](./VST3-Architecture.md#the-iunknown-pattern)
- [Multi-Interface Objects](./VST3-Architecture.md#multi-interface-objects)
- [VST3 Plugin Architecture](./VST3-Architecture.md#vst3-plugin-architecture)
- [Implementing in Zig](./VST3-Architecture.md#implementing-in-zig)
- [Complete VST3 Example](./VST3-Architecture.md#complete-vst3-example)

#### Examples
- Gain plugin: [Danzig-Gain](../examples/danzig-gain/root.zig)
- Tremolo: [Real-World Examples - Tremolo](./Real-World-Guide.md#example-1-simple-tremolo-lfo-modulation)
- Soft Clipper: [Real-World Examples - Soft Clipper](./Real-World-Guide.md#example-2-soft-clipper-with-smoothing)
- Delay/Echo: [Real-World Examples - Delay](./Real-World-Guide.md#example-3-delayecho-plugin)
- EQ: [Plugin Development Guide - EQ Filter](./Danzig-Complete-Guide.md#full-example-eq-filter-plugin)

#### Troubleshooting
- [Troubleshooting](./Danzig-Complete-Guide.md#troubleshooting)
- Build issues
- Runtime issues
- Parameter problems
- Performance issues

---

## Recommended Learning Path

### For Beginners (New to VST/Audio)

1. **Start**: [Danzig Complete Guide - Quick Start](./Danzig-Complete-Guide.md#quick-start)
   - 10-minute setup and first plugin

2. **Understand**: [Danzig Complete Guide - Core Concepts](./Danzig-Complete-Guide.md#core-concepts)
   - Learn plugin lifecycle, parameters, allocators

3. **Learn API**: [Danzig Complete Guide - API Reference](./Danzig-Complete-Guide.md#api-reference)
   - Understand the Plugin class and utilities

4. **Build**: [Real-World Guide - Getting Started](./Real-World-Guide.md#getting-started-the-right-way)
   - Set up a project properly

5. **Explore Examples**: [Real-World Guide - Examples](./Real-World-Guide.md#real-world-examples)
   - Tremolo, Soft Clipper, Delay plugins

6. **Create Your Own**: Follow [Plugin Development Guide](./Danzig-Complete-Guide.md#plugin-development-guide)

### For Intermediate Users (Some VST Knowledge)

1. **Review**: [VST3 Architecture](./VST3-Architecture.md#vst3-vs-other-plugin-formats)
   - Understand why VST3 is complex, how Danzig helps

2. **Deep Dive**: [VST3 Architecture - COM](./VST3-Architecture.md#comvst-ma-fundamentals)
   - Learn what's happening under the hood

3. **Reference**: [API Reference](./Danzig-Complete-Guide.md#api-reference)
   - Use as needed for your project

4. **Optimize**: [Real-World Guide - Performance](./Real-World-Guide.md#performance-optimization)
   - Make your plugins efficient

5. **Distribute**: [Real-World Guide - Distribution](./Real-World-Guide.md#distributing-your-plugin)
   - Package and share your creation

### For Advanced Users (VST3 Experts)

1. **Architecture Review**: [VST3 Architecture - Complete](./VST3-Architecture.md)
   - See how Danzig implements VST3 abstractions

2. **Extend Danzig**: Read source code in `src/danzig/`
   - Add your own abstractions on top

3. **Advanced Examples**: [Real-World Guide - Optimization](./Real-World-Guide.md#performance-optimization)
   - SIMD, denormals, profiling

4. **Threading**: [Advanced Topics - Multi-threading](./Danzig-Complete-Guide.md#multi-threading-considerations)
   - Lock-free UI communication

---

## Document Quick Reference

### [Danzig-Complete-Guide.md](./Danzig-Complete-Guide.md)
**Type**: Tutorial + Reference
**Length**: ~26 KB
**Topics**: 
- Full installation and setup guide
- Quick start in 10 minutes
- Complete API reference
- Plugin development walkthrough
- Audio processing techniques
- Parameter system deep dive
- Build and deployment
- Advanced topics
- Troubleshooting

**Best for**: Learning Danzig from scratch, API reference, how to build different plugin types

### [VST3-Architecture.md](./VST3-Architecture.md)
**Type**: Technical Deep Dive
**Length**: ~22 KB
**Topics**:
- VST3 vs other plugin formats
- COM (Component Object Model) explained
- GUIDs and interface IDs
- Virtual tables (VTables)
- IUnknown pattern
- Multi-interface objects
- Implementing VST3 in Zig
- Complete working example
- Why COM/VST3 is complex

**Best for**: Understanding VST3 architecture, learning COM, implementing custom interfaces

### [Real-World-Guide.md](./Real-World-Guide.md)
**Type**: Practical Guide
**Length**: ~18 KB
**Topics**:
- Project setup templates
- Common pitfalls and how to fix them
- 3 complete, real-world plugin examples
- Performance optimization techniques
- Testing strategies
- Debugging techniques
- Multi-threading considerations
- Distribution and packaging

**Best for**: Avoiding mistakes, practical implementation, complete working examples, performance tuning

---

## Code Examples by Plugin Type

### Utility Plugins
- **Gain**: See `examples/danzig-gain/root.zig`
- **Pass-through**: [Real-World Guide - Project Template](./Real-World-Guide.md#project-template)

### Effects
- **Tremolo**: [Real-World Guide - Example 1](./Real-World-Guide.md#example-1-simple-tremolo-lfo-modulation)
- **Soft Clipper**: [Real-World Guide - Example 2](./Real-World-Guide.md#example-2-soft-clipper-with-smoothing)
- **EQ**: [Complete Guide - EQ Example](./Danzig-Complete-Guide.md#full-example-eq-filter-plugin)
- **Delay/Echo**: [Real-World Guide - Example 3](./Real-World-Guide.md#example-3-delayecho-plugin)

### Generators & Processors
- **Synthesizer Skeleton**: [Complete Guide - Compressor](./Danzig-Complete-Guide.md#compressor-skeleton)

---

## API Cheat Sheet

### Creating a Plugin
```zig
const MyPlugin = struct {
    plugin: danzig.Plugin,
    
    pub fn init(allocator) !*MyPlugin {
        const self = try allocator.create(MyPlugin);
        self.plugin = danzig.Plugin.init(allocator);
        return self;
    }
};
```

### Adding Parameters
```zig
try plugin.addParameter(.{
    .id = 0,
    .minValue = -48.0,
    .maxValue = 12.0,
    .defaultValue = 0.0,
});
```

### Processing Audio
```zig
pub fn process(self, inputs, outputs, channels, samples) void {
    for (0..channels) |ch| {
        for (0..samples) |s| {
            outputs[ch][s] = self.dsp(inputs[ch][s]);
        }
    }
}
```

### Handling Parameters
```zig
pub fn setParameterNormalized(self, id, normalized) void {
    const plain = danzig.denormalize(normalized, -48.0, 12.0);
    // Use plain value
}
```

### Building
```bash
bash gen_build_spec.sh
zig build
# Output: zig-out/lib/libplugin_name.dylib
```

---

## External Resources

### VST3 & Audio
- [VST3 Official Documentation](https://steinbergmedia.github.io/vst3_dev_portal/)
- [Steinberg VST3 C API](https://github.com/steinbergmedia/vst3_c_api)
- [COM in Plain C](https://www.codeproject.com/Articles/13601/COM-in-plain-C) - Jeff Glatt's seminal article
- [Audio DSP Learning](https://www.dsprelated.com/)
- [CLAP Plugin Standard](https://cleveraudio.org/)

### Zig Language
- [Zig Language](https://ziglang.org/)
- [Zig Documentation](https://ziglang.org/documentation/)
- [Zig Standard Library](https://ziglang.org/docs/master/)

### VST3 + Zig Articles
- [Superelectric VST3/COM/Zig Post](https://superelectric.dev/post/post1.html) - Excellent reference for this framework

---

## Support & Contribution

### Finding Answers

1. **Quick lookup**: Check [API Reference](./Danzig-Complete-Guide.md#api-reference)
2. **How-to**: Check [Real-World Guide](./Real-World-Guide.md)
3. **Understanding concepts**: Check [VST3 Architecture](./VST3-Architecture.md)
4. **Debugging**: Check [Troubleshooting](./Danzig-Complete-Guide.md#troubleshooting)
5. **Examples**: Check [Real-World Examples](./Real-World-Guide.md#real-world-examples)

### Common Questions

**Q: How do I add a parameter?**
A: See [Parameter System](./Danzig-Complete-Guide.md#parameter-system) and [Real-World Guide - Example 1](./Real-World-Guide.md#example-1-simple-tremolo-lfo-modulation)

**Q: How do I process audio?**
A: See [Audio Processing](./Danzig-Complete-Guide.md#audio-processing) and [Real-World Examples](./Real-World-Guide.md#real-world-examples)

**Q: What's happening under the hood?**
A: See [VST3 Architecture](./VST3-Architecture.md)

**Q: How do I avoid common mistakes?**
A: See [Common Pitfalls](./Real-World-Guide.md#common-pitfalls)

**Q: How do I optimize for performance?**
A: See [Performance Optimization](./Real-World-Guide.md#performance-optimization)

---

## Document Versions

- **Danzig Version**: 1.0
- **Zig Requirement**: 0.14.0+
- **VST3**: 3.7.0+
- **Last Updated**: 2026-03-15
- **Documentation Status**: Complete ✅

---

## Quick Links

- **Framework Homepage**: [Danzig README](../DANZIG.md)
- **Example Plugin**: [danzig-gain](../examples/danzig-gain/)
- **Source Code**: [danzig library](../src/danzig/)
- **Build System**: [Azazel](../)

---

**Happy plugin development! 🎵**
