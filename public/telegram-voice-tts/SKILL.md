---
name: telegram-voice-tts
description: Generate high-quality Telegram voice notes (bubbles) using Microsoft Edge TTS and FFmpeg. Use when asked to send audio as a voice message, or when the user requires voice-bar replies instead of audio files. Handles edge-tts generation and OGG/Opus conversion for native Telegram voice compatibility.
---

# Telegram Voice TTS

This skill provides a workflow for generating native Telegram voice notes.

## Workflow

1. Use `scripts/telegram_voice.py` to generate an OGG/Opus file:
   ```bash
   python3 scripts/telegram_voice.py "Text to speak" "path/to/output.ogg"
   ```
2. Send the resulting file using the `message` tool:
   - Set `asVoice: true`
   - Include `[[audio_as_voice]]` in the message text
   - Provide the local `filePath` to the OGG file

## Requirements

- `edge-tts` (Python package)
- `ffmpeg` (System binary)
