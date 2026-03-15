# DanzigGain Web UI

Beautiful, modern web interface for the DanzigGain audio processor. Works with both the VST3 plugin and standalone CLI app.

## Features

✨ **Real-time Gain Control** - Smooth slider from -48 to +48 dB  
✨ **Visual Feedback** - Live waveform visualization responds to gain changes  
✨ **Drag & Drop** - Drop WAV files directly on the interface  
✨ **Responsive Design** - Works on desktop and mobile  
✨ **Shared Between Modes** - Same UI for plugin and standalone  

## Quick Start

### Option 1: Standalone Mode (Recommended)

```bash
# From the danzig project directory
cd ui
python3 server.py
```

Then open http://localhost:8000 in your browser.

### Option 2: Standalone CLI + Web UI

```bash
# Terminal 1: Start the web server
cd ui
python3 server.py

# Terminal 2: Use the standalone audio processor
../zig-out/bin/danzig-gain-standalone input.wav output.wav 6.0
```

### Option 3: VST3 Plugin with UI

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
- `server.py` - Python HTTP server with CORS support

## Server

The Python server:
- Serves static files from the UI directory
- Handles CORS for cross-origin requests
- Ready for API endpoint expansion
- No external dependencies required

To run on a different port:

```bash
python3 -c "
import http.server, socketserver
PORT = 9000  # Change this
Handler = http.server.SimpleHTTPRequestHandler
with socketserver.TCPServer(('', PORT), Handler) as httpd:
    print(f'Serving on port {PORT}...')
    httpd.serve_forever()
"
```

## Customization

Edit `index.html` to customize:

- **Colors**: Change gradient colors in `background` CSS
- **Gain Range**: Modify `min="-48"` and `max="48"` on the range input
- **Visualization**: Edit the `updateWaveformVisualization()` function
- **Layout**: Adjust padding/margin/width as needed

## API Integration

The UI posts to `http://localhost:8765/process` when available. To connect your own backend:

```javascript
// In index.html, modify the fetch URL
const response = await fetch('YOUR_SERVER/api/process', {
    method: 'POST',
    body: formData
});
```

## Development

To modify and test:

1. Edit `index.html` directly (it's a single file)
2. Run `python3 server.py`
3. Refresh browser to see changes
4. Browser DevTools (F12) shows any console errors

## License

Same as DanzigGain framework.

---

**Ready to process audio!** 🎵
