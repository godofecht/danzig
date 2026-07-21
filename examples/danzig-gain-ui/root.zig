// DanzigGain Standalone App
// Native window with embedded WebView + CoreAudio device enumeration

const std = @import("std");
const danzig = @import("danzig");
const webview = @import("webview");
const coreaudio = @import("coreaudio");

const UI_HTML: [:0]const u8 = @embedFile("ui_html");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const allocator = gpa.allocator();

    const wv = webview.WebView.create(true, null);
    defer wv.destroy() catch {};

    try wv.setTitle("DanzigGain");
    try wv.setSize(600, 700, .fixed);

    // Enumerate CoreAudio devices and inject into JS before loading UI
    const devices = coreaudio.enumerateDevices(allocator) catch &[_]coreaudio.AudioDevice{};
    const json = coreaudio.devicesToJson(allocator, devices) catch "{}";

    // Inject the device list as a global JS variable, then load the HTML
    var init_js_buf: [8192]u8 = undefined;
    const init_js = std.fmt.bufPrintZ(&init_js_buf,
        "window.__audioDevices = {s};",
        .{json},
    ) catch "window.__audioDevices = {};";
    try wv.init(init_js);

    try wv.setHtml(UI_HTML);

    std.debug.print("DanzigGain standalone app running.\n", .{});

    try wv.run();
}
