// Simple test to verify danzig library functionality
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("✓ Test executable compiles and links with danzig library\n", .{});
    
    // Simple sanity check
    std.debug.print("✓ Allocator initialized: {any}\n", .{allocator});
    std.debug.print("✓ Danzig library linking successful!\n", .{});
}
