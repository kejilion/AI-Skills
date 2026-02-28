#!/usr/bin/env bash
# Setup dependencies for video-talk-editor
set -euo pipefail

echo "=== Video Talk Editor: Installing dependencies ==="

# Check Python version
PYVER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "Python version: $PYVER"

# Install faster-whisper and deps
echo "Installing faster-whisper..."
pip3 install --break-system-packages -q \
  faster-whisper \
  pysrt \
  jieba \
  numpy 2>/dev/null || \
pip3 install \
  faster-whisper \
  pysrt \
  jieba \
  numpy

# Verify ffmpeg
if ! command -v ffmpeg &>/dev/null; then
  echo "ERROR: ffmpeg not found. Install it first:"
  echo "  apt install ffmpeg   # Debian/Ubuntu"
  echo "  brew install ffmpeg  # macOS"
  exit 1
fi

echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -1)"

# Verify installs
python3 -c "from faster_whisper import WhisperModel; print('faster-whisper: OK')"
python3 -c "import pysrt; print('pysrt: OK')"
python3 -c "import jieba; print('jieba: OK')"

echo ""
echo "=== Setup complete ==="
echo "Note: The whisper model will be downloaded on first transcription (~1.5GB for large-v3)"
