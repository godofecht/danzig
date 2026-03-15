# DanzigGain Web UI

Beautiful, modern web interface for the DanzigGain audio processor. Works with both the VST3 plugin and standalone CLI app.

## Features

✨ **Real-time Gain Control** - Smooth slider from -48 to +48 dB  
✨ **Visual Feedback** - Live waveform visualization responds to gain changes  
✨ **Drag & Drop** - Drop WAV files directly on the interface  
✨ **Responsive Design** - Works on desktop and mobile  
✨ **Shared Between Modes** - Same UI for plugin and standalone  
✨ **Native Zig Server** - Zero external dependencies, pure stdlib HTTP server

## Quick Start

### Zig Native HTTP Server (Recommended)

```bash
# From the danzig project directory
zig build -Doptimize=ReleaseFast
./zig-out/bin/danzig-webui
```

Then open http://localhost:3000 in your browser.

### With Standalone Audio Processing

```bash
# Terminal 1: Start the web server
zig build -Doptimize=ReleaseFast
./zig-out/bin/danzig-webui

# Terminal 2: Use the standalone audio processor (if needed)
./zig-out/bin/danzig-gain-standalone input.wav output.wav 6.0
```

### VST3 Plugin with UI

The UI automatically detects when loaded as a VST3 plugin UI and switches to plugin mode (parameter only, no file processing).

## Usage

### Web UI Controls

1. **Gain Slider** - Adjust from -48 to +48 dB
   - Real-time visualization updates
   - Shows current gain value in dB

2. **File Selection** (Standalone mode only)
   - Click to browse files
   - Or drag & drop WAV files directly
   - Supports 32-bit float PCM WAV files

3. **Process Button** (Standalone mode only)
   - Processes the selected file with current gain
   - Downloads processed file automatically

4. **Reset Button**
   - Returns gain to 0 dB
   - Clears file selection
   - Resets UI state

## Architecture

The UI is mode-aware:

```
┌─────────────────────────────────────────┐
│         DanzigGain Web UI               │
├─────────────────────────────────────────┤
│                                         │
│  ┌────────────────┐  ┌──────────────┐  │
│  │  VST3 Mode     │  │ Standalone   │  │
│  │                │  │    Mode      │  │
│  │ • Gain slider  │  │ • File input │  │
│  │ • Send to host │  │ • Process    │  │
│  │                │  │ • Download   │  │
│  └────────────────┘  └──────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

## Server Implementation

The HTTP server is implemented in pure Zig using `std.net`:

- **Language**: Zig (no external dependencies)
- **Port**: 3000 (configurable in `examples/danzig-webui/root.zig`)
- **Features**: GET/POST/OPTIONS handling, CORS support, HTML embedding
- **Startup**: `./zig-out/bin/danzig-webui` from project root
- **Architecture**: Single-threaded TCP server (suitable for development/testing)

### Server Source

Located in `examples/danzig-webui/root.zig` - a self-contained HTTP server that:
- Loads UI HTML at startup from `ui/index.html`
- Serves GET requests with proper HTTP headers
- Handles CORS for cross-origin requests
- Prepared for audio processing API endpoints

## Styling

The UI uses:
- **Colors**: Purple gradient (#667eea → #764ba2)
- **Typography**: System fonts for maximum performance
- **Animations**: Smooth transitions and hover effects
- **Responsive**: Adapts from 300px to 500px width

## Browser Support

- Chrome/Chromium 90+
- Firefox 88+
- Safari 14+
- Edge 90+
- Mobile browsers (iOS Safari 13+, Chrome Mobile)

## Files

- `index.html` - Complete UI with embedded CSS and JavaScript
- `../examples/danzig-webui/root.zig` - Native Zig HTTP server

## Customization

Edit `index.html` to customize:

- **Colors**: Change gradient colors in `background` CSS
- **Gain Range**: Modify `min="-48"` and `max="48"` on the range input
- **Visualization**: Edit the `updateWaveformVisualization()` function
- **Layout**: Adjust padding/margin/width as needed

To change the server port, edit `const PORT` in `examples/danzig-webui/root.zig` and rebuild.

## API Integration

The UI is prepared for backend integration. To add audio processing endpoints:

1. Edit `handleConnection()` in `examples/danzig-webui/root.zig`
2. Add handlers for POST `/api/process`
3. Integrate with danzig audio processing
4. Rebuild: `zig build -Doptimize=ReleaseFast`

## Development

To modify and test:

1. Edit `index.html` directly (it's a single file)
2. Rebuild: `zig build -Doptimize=ReleaseFast`
3. Run: `./zig-out/bin/danzig-webui`
4. Refresh browser to see changes
5. Browser DevTools (F12) shows any console errors

## License

Same as DanzigGain framework.

---

**Ready to process audio!** 🎵

