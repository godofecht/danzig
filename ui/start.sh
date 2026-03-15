#!/bin/bash
# Quick start script for DanzigGain Web UI

cd "$(dirname "$0")"

echo ""
echo "🎵 DanzigGain Web UI"
echo "===================="
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is not installed"
    exit 1
fi

# Check if server.py exists
if [ ! -f "server.py" ]; then
    echo "❌ Error: server.py not found"
    exit 1
fi

echo "✓ Starting web server..."
echo ""
echo "📱 Open your browser to: http://localhost:8000"
echo "🎛️  Use the UI to process audio files"
echo "⏹️  Press Ctrl+C to stop"
echo ""

python3 server.py
