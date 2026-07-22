# danzig-webui

An HTTP server written against `std.net` alone, serving the danzig web UI.

## What it demonstrates

A plugin UI has to come from somewhere. One option is HTML in a WebView, which
means you need something to serve it during development. This example is that
something, in 150 lines of Zig with no dependency beyond the standard library.

It loads `ui/index.html` at startup, listens on `127.0.0.1:3000`, and handles
GET, POST, and OPTIONS with CORS headers. `/api/process` is stubbed and returns
a fixed JSON body, ready to be wired to the DSP.

One detail worth copying. The request read uses `stream.read` rather than
`readAll`:

```zig
// A single read rather than readAll: readAll blocks until the buffer is
// full or the peer closes, which for a keep-alive HTTP client means
// hanging. It was also removed from net.Stream in Zig 0.15.
const bytes_read = try stream.read(&buffer);
```

`readAll` on a keep-alive connection waits for a close that never comes.

## Build and run

The server reads `ui/index.html` from a relative path, so run it from the
repository root.

```bash
zig build
./zig-out/bin/danzig-webui
```

```
🎵 DanzigGain Web Server
========================
🌐 Open http://localhost:3000
⏹️  Press Ctrl+C to stop
```

Then open <http://localhost:3000>.

## Check it from the shell

```bash
curl -s -D- -o /dev/null http://127.0.0.1:3000/
```

```
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: 15787
Access-Control-Allow-Origin: *
```

## The port

3000 is a constant at the top of `root.zig`. If something else already holds
it, requests will reach the other service instead of this one, which looks like
the server serving the wrong page. Check first:

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

Change `const PORT` and rebuild to move it.

## Limits

- Single-threaded. It handles one connection at a time. Fine for development.
- No routing beyond the four cases in `handleConnection`.
- `/api/process` returns `{"status":"ok","processed":true}` without touching
  audio.

## Related

`ui/index.html` is the page itself, and `ui/README.md` documents its controls.
The same file is embedded into `../danzig-gain-ui`, which renders it in a
native window with no server involved.

---

See [docs/WIKI.md](../../docs/WIKI.md) for the rest of the project.
