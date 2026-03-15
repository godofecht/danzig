# Danzig VST3 Architecture Deep Dive

Comprehensive guide to VST3, COM (Component Object Model), and how Danzig abstracts them in Zig.

## Table of Contents

1. [VST3 vs Other Plugin Formats](#vst3-vs-other-plugin-formats)
2. [COM/VST-MA Fundamentals](#comvst-ma-fundamentals)
3. [GUIDs and Interface IDs](#guids-and-interface-ids)
4. [Virtual Tables (VTables)](#virtual-tables-vtables)
5. [The IUnknown Pattern](#the-iunknown-pattern)
6. [Multi-Interface Objects](#multi-interface-objects)
7. [VST3 Plugin Architecture](#vst3-plugin-architecture)
8. [Factory Pattern](#factory-pattern)
9. [Implementing in Zig](#implementing-in-zig)
10. [Complete VST3 Example](#complete-vst3-example)

---

## VST3 vs Other Plugin Formats

### CLAP (Clever Audio Plug-in)

**Pros:**
- Modern, open standard
- Simple C ABI
- No COM complexity
- Excellent for new projects

**Example CLAP plugin:**
```zig
pub const clap_plugin = extern struct {
    desc: *const clap_plugin_descriptor,
    plugin_data: ?*anyopaque,
    init: *const fn (*clap_plugin) callconv(.C) bool,
    destroy: *const fn (*clap_plugin) callconv(.C) void,
    activate: *const fn (*clap_plugin, sample_rate: f64, min_frame_count: u32, max_frame_count: u32) callconv(.C) bool,
    deactivate: *const fn (*clap_plugin) callconv(.C) void,
    process: *const fn (*clap_plugin, *clap_process_t) callconv(.C) clap_process_status,
};
```

### VST3 (Steinberg Virtual Studio Technology 3)

**Pros:**
- Ubiquitous (macOS, Windows, Linux)
- Well-supported in DAWs (Cubase, Reaper, Ableton, etc.)
- Mature ecosystem
- Rich feature set via extensions

**Cons:**
- Based on COM (Microsoft's 1980s architecture)
- Complex ABI and interface system
- Requires understanding multiple inheritance patterns
- No C documentation (officially C++ only)

---

## COM/VST-MA Fundamentals

COM (Component Object Model) is Microsoft's binary object system from the 1980s. VST-MA (VST Module Architecture) is basically COM with VST-specific extensions.

### Core Concepts

1. **Interfaces**: Abstract specifications for behavior
2. **GUIDs**: Unique 16-byte identifiers
3. **VTables**: Pointers to function implementations
4. **Ref Counting**: Automatic memory management via reference counting
5. **QueryInterface**: Runtime discovery of interfaces

### Why COM?

VST3 uses COM because:
- It enables cross-language compatibility
- Objects can implement multiple interfaces
- Graceful versioning and interface evolution
- Binary stability across compiler versions

### The Catch

COM was designed for C++. Implementing it in other languages requires manual vtable management, pointer arithmetic, and careful memory handling.

---

## GUIDs and Interface IDs

### What is a GUID?

A GUID (Globally Unique IDentifier) is a 128-bit (16-byte) value intended to be unique across all software.

```
Standard Format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
Example:         550e8400-e29b-41d4-a716-446655440000

Binary: [16]u8 = 16 bytes of unique data
```

### Using GUIDs in Zig

Define a constant for each interface:

```zig
const IProcessor_IID = [16]u8{
    0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
    0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00,
};
```

Or parse from string format:

```zig
pub fn parseGuid(str: []const u8) [16]u8 {
    var last_nibble: ?u8 = null;
    var ret = [_]u8{0} ** 16;
    var idx: usize = 0;
    
    for (str) |char| {
        var nibble: u8 = 0;
        if ('A' <= char and char <= 'F') {
            nibble = char - 'A' + 10;
        } else if ('a' <= char and char <= 'f') {
            nibble = char - 'a' + 10;
        } else if ('0' <= char and char <= '9') {
            nibble = char - '0';
        } else {
            continue;
        }

        if (last_nibble) |last_val| {
            ret[idx] = last_val * 16 + nibble;
            idx += 1;
            last_nibble = null;
        } else {
            last_nibble = nibble;
        }
    }

    return ret;
}

// Usage:
const IProcessor_IID = parseGuid("550e8400-e29b-41d4-a716-446655440000");
```

### GUID Comparison

```zig
// Compare GUIDs
if (std.mem.eql(u8, requested_iid[0..16], &IProcessor_IID)) {
    // This interface is implemented!
}
```

---

## Virtual Tables (VTables)

### What is a VTable?

A VTable is a struct of function pointers. It defines the API of an interface.

```zig
// IUnknown VTable (all interfaces inherit this)
const IUnknownVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.C) i32,
    addRef: *const fn (*anyopaque) callconv(.C) u32,
    release: *const fn (*anyopaque) callconv(.C) u32,
};

// IProcessor extends IUnknown
const IProcessorVTable = extern struct {
    // IUnknown methods first
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.C) i32,
    addRef: *const fn (*anyopaque) callconv(.C) u32,
    release: *const fn (*anyopaque) callconv(.C) u32,
    
    // IProcessor-specific methods
    process: *const fn (*anyopaque, *ProcessData) callconv(.C) i32,
    activate: *const fn (*anyopaque) callconv(.C) i32,
    deactivate: *const fn (*anyopaque) callconv(.C) i32,
};
```

### Interface Definition

An interface is a struct containing a pointer to its VTable:

```zig
const IProcessor = extern struct {
    lpVtbl: *const IProcessorVTable,
};

const IUnknown = extern struct {
    lpVtbl: *const IUnknownVTable,
};
```

### Calling Methods Through VTable

```zig
// Get the vtable pointer
let vtable = interface.lpVtbl;

// Call a method
let result = vtable.process(@ptrCast(interface_ptr), process_data);
```

---

## The IUnknown Pattern

IUnknown is the base interface that all COM objects must implement.

### Three Essential Methods

```zig
pub fn queryInterface(
    self: *anyopaque,
    iid: [*]const u8,
    obj: *?*anyopaque
) callconv(.C) i32
```
**Purpose**: Query if object implements interface with given GUID
- `iid`: 16-byte interface ID to check
- `obj`: Output pointer to interface (if found)
- **Returns**: 0 if found, non-zero if not supported

```zig
pub fn addRef(self: *anyopaque) callconv(.C) u32
```
**Purpose**: Increment reference count
- Called when someone holds a reference
- Prevents premature deletion
- **Returns**: New reference count

```zig
pub fn release(self: *anyopaque) callconv(.C) u32
```
**Purpose**: Decrement reference count
- Called when done using interface
- Delete object when count reaches 0
- **Returns**: New reference count

### Reference Counting Example

```zig
// Host creates plugin
var plugin: *IProcessor = getPluginInstance();

// Each time a module uses it, addRef is called
plugin.lpVtbl.addRef(@ptrCast(plugin));      // ref_count = 1
plugin.lpVtbl.addRef(@ptrCast(plugin));      // ref_count = 2

// When done, release is called
plugin.lpVtbl.release(@ptrCast(plugin));     // ref_count = 1
plugin.lpVtbl.release(@ptrCast(plugin));     // ref_count = 0, object deleted
```

---

## Multi-Interface Objects

### The Problem

An object might implement multiple interfaces:
- IProcessor (audio processing)
- IEditController (parameters)
- IComponent (plugin info)

Each interface has its own VTable, and all share the same underlying object.

### The Solution: Pointer Arithmetic

```zig
pub struct Object {
    i_processor: IProcessor;
    i_controller: IEditController;
    
    // Implementation data
    state: f32;
};

fn queryInterface(
    self: *anyopaque,
    iid: [*]const u8,
    obj: *?*anyopaque
) callconv(.C) i32 {
    let obj_ptr = @as(*Object, @ptrCast(self));
    
    // Interface 1: IProcessor
    if (std.mem.eql(u8, iid[0..16], &IProcessor_IID)) {
        let processor_ptr = &obj_ptr.i_processor;
        obj.* = @ptrCast(processor_ptr);
        return 0;  // Success
    }
    
    // Interface 2: IEditController
    if (std.mem.eql(u8, iid[0..16], &IEditController_IID)) {
        let controller_ptr = &obj_ptr.i_controller;
        obj.* = @ptrCast(controller_ptr);
        return 0;  // Success
    }
    
    return 1;  // Not supported
}
```

**Key insight**: Each interface is literally just a struct with a VTable pointer. The object stores multiple such structs, and queryInterface returns a pointer to the appropriate one.

### Complete Multi-Interface Example

```zig
const Object = struct {
    // Two interfaces
    i_add: IAdd,
    i_sub: ISub,
    
    // Shared implementation
    value: i32 = 0,
};

fn IAdd_add(self: *anyopaque, a: i32, b: i32) callconv(.C) i32 {
    let obj_ptr = @as(*Object, @ptrCast(self));
    return a + b;
}

fn ISub_sub(self: *anyopaque, a: i32, b: i32) callconv(.C) i32 {
    let obj_ptr = @as(*Object, @ptrCast(self));
    return a - b;
}

fn queryInterface(
    self: *anyopaque,
    iid: [*]const u8,
    obj: *?*anyopaque
) callconv(.C) i32 {
    // Object is stored as first interface
    let obj_ptr = @as(*Object, @ptrCast(self));
    
    // Return pointer to IAdd
    if (std.mem.eql(u8, iid[0..16], &IAdd_IID)) {
        obj.* = @ptrCast(&obj_ptr.i_add);
        return 0;
    }
    
    // Return pointer to ISub
    if (std.mem.eql(u8, iid[0..16], &ISub_IID)) {
        obj.* = @ptrCast(&obj_ptr.i_sub);
        return 0;
    }
    
    return 1;
}
```

---

## VST3 Plugin Architecture

### Entry Point: GetPluginFactory

```zig
// This is the only exported function from your shared library
pub export fn GetPluginFactory() ?*anyopaque {
    return @ptrCast(&PLUGIN_FACTORY);
}

const PLUGIN_FACTORY: IPluginFactory = .{
    .lpVtbl = &plugin_factory_vtbl,
};
```

### The Plugin Factory

```zig
const IPluginFactoryVTable = extern struct {
    // IUnknown methods
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.C) i32,
    addRef: *const fn (*anyopaque) callconv(.C) u32,
    release: *const fn (*anyopaque) callconv(.C) u32,
    
    // IPluginFactory methods
    getFactoryInfo: *const fn (*anyopaque, *FactoryInfo) callconv(.C) i32,
    countClasses: *const fn (*anyopaque) callconv(.C) i32,
    getClassInfo: *const fn (*anyopaque, i32, *ClassInfo) callconv(.C) i32,
    createInstance: *const fn (*anyopaque, [*]const u8, [*]const u8, *?*anyopaque) callconv(.C) i32,
};
```

**Methods:**
- `countClasses()`: How many plugin classes does this library have?
- `getClassInfo(index)`: Get info about plugin at index
- `createInstance(cid, iid)`: Create an instance of class `cid`, returning interface `iid`

### Two Main Objects

#### 1. IComponent (Processor)

Handles audio processing:
```zig
const IComponentVTable = extern struct {
    // Base methods
    queryInterface: ...,
    addRef: ...,
    release: ...,
    
    // Component methods
    getControllerClassId: *const fn (*anyopaque, [*]u8) callconv(.C) i32,
    setIoMode: *const fn (*anyopaque, i32) callconv(.C) i32,
    getBusCount: *const fn (*anyopaque, i32, u32) callconv(.C) u32,
    getBusInfo: *const fn (*anyopaque, i32, u32, *BusInfo) callconv(.C) i32,
    setActive: *const fn (*anyopaque, u8) callconv(.C) i32,
    setState: *const fn (*anyopaque, *anyopaque) callconv(.C) i32,
    getState: *const fn (*anyopaque, *anyopaque) callconv(.C) i32,
};
```

#### 2. IEditController

Manages parameters:
```zig
const IEditControllerVTable = extern struct {
    // Base methods
    queryInterface: ...,
    addRef: ...,
    release: ...,
    
    // Controller methods
    setComponentState: *const fn (*anyopaque, *anyopaque) callconv(.C) i32,
    setState: *const fn (*anyopaque, *anyopaque) callconv(.C) i32,
    getState: *const fn (*anyopaque, *anyopaque) callconv(.C) i32,
    getParameterCount: *const fn (*anyopaque) callconv(.C) i32,
    getParameterInfo: *const fn (*anyopaque, i32, *ParameterInfo) callconv(.C) i32,
    getParamNormalized: *const fn (*anyopaque, u32) callconv(.C) f64,
    setParamNormalized: *const fn (*anyopaque, u32, f64) callconv(.C) i32,
};
```

---

## Factory Pattern

### Plugin Library Structure

```
YourPlugin.vst3/
├── plugin.zig          ← Your code
├── interfaces.zig      ← COM interfaces
└── factory.zig         ← Plugin factory
```

### Factory Implementation

```zig
pub const PluginFactory = struct {
    pub fn getClassInfo(self: *anyopaque, index: i32, info: *ClassInfo) i32 {
        if (index == 0) {
            // First class: our processor
            info.cid = PROCESSOR_CID;
            info.cardinality = 0x7FFFFFFF;  // Unlimited instances
            // ... set name, version, etc
            return 0;
        }
        return 1;  // Not found
    }
    
    pub fn createInstance(
        self: *anyopaque,
        cid: [*]const u8,
        iid: [*]const u8,
        obj: *?*anyopaque
    ) i32 {
        // Create our processor
        if (std.mem.eql(u8, cid[0..16], &PROCESSOR_CID)) {
            let processor = createProcessor();
            return processor.queryInterface(iid, obj);
        }
        return 1;
    }
};
```

---

## Implementing in Zig

### Step 1: Define Interfaces

```zig
const IProcessor = extern struct {
    lpVtbl: *const IProcessorVTable,
};

const IProcessorVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.C) i32,
    addRef: *const fn (*anyopaque) callconv(.C) u32,
    release: *const fn (*anyopaque) callconv(.C) u32,
    
    process: *const fn (*anyopaque, *ProcessData) callconv(.C) i32,
    activate: *const fn (*anyopaque) callconv(.C) i32,
    deactivate: *const fn (*anyopaque) callconv(.C) i32,
};
```

### Step 2: Implement Plugin Object

```zig
pub const MyPlugin = struct {
    i_processor: IProcessor,
    
    // State
    ref_count: u32 = 1,
    state: f32 = 0.0,
};

fn myPlugin_queryInterface(
    self: *anyopaque,
    iid: [*]const u8,
    obj: *?*anyopaque
) callconv(.C) i32 {
    let plugin = @as(*MyPlugin, @ptrCast(self));
    
    if (std.mem.eql(u8, iid[0..16], &IProcessor_IID)) {
        obj.* = @ptrCast(&plugin.i_processor);
        return 0;  // kResultOk
    }
    
    return 1;  // kResultFalse
}

fn myPlugin_addRef(self: *anyopaque) callconv(.C) u32 {
    let plugin = @as(*MyPlugin, @ptrCast(self));
    plugin.ref_count += 1;
    return plugin.ref_count;
}

fn myPlugin_release(self: *anyopaque) callconv(.C) u32 {
    let plugin = @as(*MyPlugin, @ptrCast(self));
    plugin.ref_count -= 1;
    
    if (plugin.ref_count == 0) {
        // Cleanup
    }
    
    return plugin.ref_count;
}

fn myPlugin_process(self: *anyopaque, data: *ProcessData) callconv(.C) i32 {
    let plugin = @as(*MyPlugin, @ptrCast(self));
    // Audio processing here
    return 0;  // kResultOk
}

// VTable initialization
const myPlugin_vtbl = IProcessorVTable{
    .queryInterface = myPlugin_queryInterface,
    .addRef = myPlugin_addRef,
    .release = myPlugin_release,
    .process = myPlugin_process,
    .activate = myPlugin_activate,
    .deactivate = myPlugin_deactivate,
};
```

### Step 3: Metaprogramming for Simplicity

Create a helper to reduce boilerplate:

```zig
pub fn createUnknown(
    comptime T: type,
    comptime Interfaces: type,
    impl: *const Interfaces
) T {
    return T{ .lpVtbl = impl };
}

// Usage becomes:
pub fn MyPluginFactory() IProcessor {
    return createUnknown(IProcessor, IProcessorVTable, &myPlugin_vtbl);
}
```

---

## Complete VST3 Example

```zig
const std = @import("std");

// ============================================================================
// INTERFACE DEFINITIONS
// ============================================================================

const IProcessor = extern struct {
    lpVtbl: *const IProcessorVTable,
};

const IProcessorVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.C) i32,
    addRef: *const fn (*anyopaque) callconv(.C) u32,
    release: *const fn (*anyopaque) callconv(.C) u32,
    process: *const fn (*anyopaque, *ProcessData) callconv(.C) i32,
    activate: *const fn (*anyopaque) callconv(.C) i32,
    deactivate: *const fn (*anyopaque) callconv(.C) i32,
};

const IPluginFactory = extern struct {
    lpVtbl: *const IPluginFactoryVTable,
};

const IPluginFactoryVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*]const u8, *?*anyopaque) callconv(.C) i32,
    addRef: *const fn (*anyopaque) callconv(.C) u32,
    release: *const fn (*anyopaque) callconv(.C) u32,
    countClasses: *const fn (*anyopaque) callconv(.C) i32,
    getClassInfo: *const fn (*anyopaque, i32, *ClassInfo) callconv(.C) i32,
    createInstance: *const fn (*anyopaque, [*]const u8, [*]const u8, *?*anyopaque) callconv(.C) i32,
};

const ProcessData = extern struct {
    numSamples: i32,
    numInputs: u32,
    numOutputs: u32,
    inputs: [*]AudioBusBuffers,
    outputs: [*]AudioBusBuffers,
};

const AudioBusBuffers = extern struct {
    numChannels: u32,
    channelBuffers32: [*][*]f32,
};

const ClassInfo = extern struct {
    cid: [16]u8,
    cardinality: i32,
    name: [64]u8,
};

// ============================================================================
// PLUGIN IMPLEMENTATION
// ============================================================================

const GainPlugin = struct {
    i_processor: IProcessor,
    ref_count: u32 = 1,
    gain: f32 = 1.0,
};

fn gainPlugin_queryInterface(
    self: *anyopaque,
    iid: [*]const u8,
    obj: *?*anyopaque
) callconv(.C) i32 {
    let plugin = @as(*GainPlugin, @ptrCast(self));
    
    // Return processor interface
    obj.* = @ptrCast(&plugin.i_processor);
    return 0;
}

fn gainPlugin_addRef(self: *anyopaque) callconv(.C) u32 {
    let plugin = @as(*GainPlugin, @ptrCast(self));
    plugin.ref_count += 1;
    return plugin.ref_count;
}

fn gainPlugin_release(self: *anyopaque) callconv(.C) u32 {
    let plugin = @as(*GainPlugin, @ptrCast(self));
    plugin.ref_count -= 1;
    return plugin.ref_count;
}

fn gainPlugin_process(self: *anyopaque, data: *ProcessData) callconv(.C) i32 {
    let plugin = @as(*GainPlugin, @ptrCast(self));
    
    // Process each input sample
    for (0..@intCast(data.numOutputs)) |o| {
        for (0..@intCast(data.outputs[o].numChannels)) |c| {
            for (0..@intCast(data.numSamples)) |s| {
                data.outputs[o].channelBuffers32[c][s] = 
                    data.inputs[0].channelBuffers32[c][s] * plugin.gain;
            }
        }
    }
    
    return 0;  // kResultOk
}

fn gainPlugin_activate(self: *anyopaque) callconv(.C) i32 {
    _ = self;
    return 0;
}

fn gainPlugin_deactivate(self: *anyopaque) callconv(.C) i32 {
    _ = self;
    return 0;
}

const gainPlugin_vtbl = IProcessorVTable{
    .queryInterface = gainPlugin_queryInterface,
    .addRef = gainPlugin_addRef,
    .release = gainPlugin_release,
    .process = gainPlugin_process,
    .activate = gainPlugin_activate,
    .deactivate = gainPlugin_deactivate,
};

// ============================================================================
// FACTORY IMPLEMENTATION
// ============================================================================

const PROCESSOR_CID = [16]u8{
    1, 2, 3, 4, 5, 6, 7, 8,
    9, 10, 11, 12, 13, 14, 15, 16,
};

fn factory_countClasses(self: *anyopaque) callconv(.C) i32 {
    _ = self;
    return 1;  // One plugin class
}

fn factory_getClassInfo(
    self: *anyopaque,
    index: i32,
    info: *ClassInfo
) callconv(.C) i32 {
    _ = self;
    
    if (index == 0) {
        info.cid = PROCESSOR_CID;
        info.cardinality = 0x7FFFFFFF;
        @memcpy(info.name[0..8], "GainPLG\x00");
        return 0;
    }
    
    return 1;
}

fn factory_createInstance(
    self: *anyopaque,
    cid: [*]const u8,
    iid: [*]const u8,
    obj: *?*anyopaque
) callconv(.C) i32 {
    _ = self;
    _ = iid;
    
    // Check if CID matches our processor
    if (std.mem.eql(u8, cid[0..16], &PROCESSOR_CID)) {
        var plugin: *GainPlugin = @ptrCast(allocator.create(GainPlugin) catch return 1);
        plugin.i_processor.lpVtbl = &gainPlugin_vtbl;
        obj.* = @ptrCast(&plugin.i_processor);
        return 0;
    }
    
    return 1;
}

const factory_vtbl = IPluginFactoryVTable{
    .queryInterface = undefined,
    .addRef = undefined,
    .release = undefined,
    .countClasses = factory_countClasses,
    .getClassInfo = factory_getClassInfo,
    .createInstance = factory_createInstance,
};

var factory = IPluginFactory{
    .lpVtbl = &factory_vtbl,
};

// ============================================================================
// ENTRY POINT
// ============================================================================

var allocator: std.mem.Allocator = undefined;

pub export fn GetPluginFactory() ?*anyopaque {
    return @ptrCast(&factory);
}

pub fn main() void {
    std.debug.print("Gain Plugin Loaded\n", .{});
}
```

---

## Why This Complexity?

The COM/VST-MA architecture seems overly complex because:

1. **Binary Compatibility**: Works across C/C++/Zig/etc
2. **Versioning**: Can add new methods without breaking old code
3. **Dynamic Dispatch**: Methods resolved at runtime via VTables
4. **Multiple Inheritance**: Objects can implement multiple interfaces

## How Danzig Simplifies

The Danzig library abstracts away most COM complexity:

```zig
// What you write:
var plugin = danzig.Plugin.init(allocator);
try plugin.addParameter(param);
plugin.activate();
plugin.process(inputs, outputs, channels, samples);

// What COM requires:
// - Manual vtable creation
// - Interface inheritance
// - Reference counting
// - QueryInterface implementations
// - Pointer arithmetic
// - GUID comparisons
```

---

## Further Reading

- [Superelectric Post on VST3/COM/Zig](https://superelectric.dev/post/post1.html) - Excellent deep dive
- [VST3 Documentation](https://steinbergmedia.github.io/vst3_dev_portal/)
- [COM in Plain C](https://www.codeproject.com/Articles/13601/COM-in-plain-C) - Jeff Glatt's seminal article
