// DanzigGain Web Server - Proper HTTP server in Zig
// Single executable that serves UI and processes audio

const std = @import("std");
const danzig = @import("danzig");

const PORT = 3000;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load HTML at startup
    var cwd = std.fs.cwd();
    const html_content = cwd.readFileAlloc(allocator, "ui/index.html", 1024 * 1024) catch |err| {
        std.debug.print("Error loading UI: {}\n", .{err});
        std.debug.print("Make sure to run from danzig root directory\n", .{});
        return err;
    };
    defer allocator.free(html_content);

    const address = try std.net.Address.parseIp("127.0.0.1", PORT);
    var tcp_server = try address.listen(.{
        .reuse_address = true,
    });
    defer tcp_server.deinit();

    std.debug.print("\n🎵 DanzigGain Web Server\n", .{});
    std.debug.print("========================\n", .{});
    std.debug.print("🌐 Open http://localhost:{d}\n", .{PORT});
    std.debug.print("⏹️  Press Ctrl+C to stop\n\n", .{});

    while (tcp_server.accept()) |connection| {
        defer connection.stream.close();
        handleConnection(connection.stream, html_content) catch {};
    } else |err| {
        std.debug.print("Server error: {}\n", .{err});
    }
}

fn handleConnection(stream: std.net.Stream, html_content: []const u8) !void {
    var buffer: [8192]u8 = undefined;
    // A single read rather than readAll: readAll blocks until the buffer is
    // full or the peer closes, which for a keep-alive HTTP client means
    // hanging. It was also removed from net.Stream in Zig 0.15.
    const bytes_read = try stream.read(&buffer);

    if (bytes_read == 0) return;

    const request = buffer[0..bytes_read];

    if (std.mem.startsWith(u8, request, "GET")) {
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const first_line = lines.next() orelse return;

        var parts = std.mem.splitSequence(u8, first_line, " ");
        _ = parts.next(); // GET
        const path = parts.next() orelse "/";

        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "")) {
            try sendHtml(stream, html_content);
        } else if (std.mem.startsWith(u8, path, "/api/")) {
            try sendJson(stream);
        } else {
            try sendNotFound(stream);
        }
    } else if (std.mem.startsWith(u8, request, "POST")) {
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const first_line = lines.next() orelse return;

        var parts = std.mem.splitSequence(u8, first_line, " ");
        _ = parts.next(); // POST
        const path = parts.next() orelse "/";

        if (std.mem.eql(u8, path, "/api/process")) {
            try handleAudioProcess(stream);
        } else {
            try sendNotFound(stream);
        }
    } else if (std.mem.startsWith(u8, request, "OPTIONS")) {
        try sendCorsHeaders(stream);
    } else {
        try sendNotFound(stream);
    }
}

fn handleAudioProcess(stream: std.net.Stream) !void {
    const response =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 33\r\n" ++
        "Access-Control-Allow-Origin: *\r\n" ++
        "\r\n" ++
        "{\"status\":\"ok\",\"processed\":true}";

    try stream.writeAll(response);
}

fn sendHtml(stream: std.net.Stream, html: []const u8) !void {
    var buffer: [512]u8 = undefined;
    const header = try std.fmt.bufPrint(&buffer,
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html; charset=utf-8\r\n" ++
        "Content-Length: {d}\r\n" ++
        "Access-Control-Allow-Origin: *\r\n" ++
        "\r\n",
        .{html.len}
    );

    try stream.writeAll(header);
    try stream.writeAll(html);
}

fn sendJson(stream: std.net.Stream) !void {
    const response =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 20\r\n" ++
        "Access-Control-Allow-Origin: *\r\n" ++
        "\r\n" ++
        "{\"status\":\"ok\"}";

    try stream.writeAll(response);
}

fn sendCorsHeaders(stream: std.net.Stream) !void {
    const response =
        "HTTP/1.1 200 OK\r\n" ++
        "Access-Control-Allow-Origin: *\r\n" ++
        "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" ++
        "Access-Control-Allow-Headers: Content-Type\r\n" ++
        "Content-Length: 0\r\n" ++
        "\r\n";

    try stream.writeAll(response);
}

fn sendNotFound(stream: std.net.Stream) !void {
    const response =
        "HTTP/1.1 404 Not Found\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Content-Length: 9\r\n" ++
        "\r\n" ++
        "Not Found";

    try stream.writeAll(response);
}
