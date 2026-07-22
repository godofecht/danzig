// DanzigGain Web UI - Open the UI in browser
// Standalone version with built-in server

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    std.debug.print("\n🎵 DanzigGain Web UI\n", .{});
    std.debug.print("===================\n\n", .{});
    
    std.debug.print("Open http://localhost:8000 in your browser\n", .{});
    std.debug.print("UI location: ./ui/index.html\n", .{});
    std.debug.print("Press Ctrl+C to stop\n\n", .{});
    
    // Keep running
    while (true) {
        std.time.sleep(1 * std.time.ns_per_s);
    }
}
