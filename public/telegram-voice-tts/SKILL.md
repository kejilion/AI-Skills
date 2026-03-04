---
name: telegram-voice-tts
description: Generate high-quality Telegram voice notes (bubbles) using Microsoft Edge TTS and FFmpeg. Use when asked to send audio as a voice message, or when the user requires voice-bar replies instead of audio files. Handles edge-tts generation and OGG/Opus conversion for native Telegram voice compatibility.
---

# Telegram Voice TTS

> ⚠️ **Deprecated / 备用方案**：OpenClaw 已内置 Edge TTS（免费、无密钥），默认可用且会自动生成语音气泡。推荐直接使用内置 TTS。仅当内置 TTS 异常时，才使用本技能脚本手动生成语音。

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

---

## 推荐：OpenClaw 内置 Edge TTS 配置手册（无需本技能）

内置 TTS 支持 Edge/OpenAI/ElevenLabs，未配置 API key 时默认用 **Edge TTS**（免费）。在 Telegram 自动发语音气泡。

### 快速启用（Edge TTS）
1. 编辑 `/root/.openclaw/openclaw.json`（或对应主机配置），在 `messages.tts` 下设置：
   ```json5
   {
     "messages": {
       "tts": {
         "auto": "always",          // 每条回复都带语音
         "provider": "edge",         // 使用 Edge TTS（无密钥）
         "edge": {
           "enabled": true,
           "voice": "zh-CN-YunyangNeural",   // 中文男声（云音阳）
           "lang": "zh-CN",
           "outputFormat": "audio-24khz-48kbitrate-mono-mp3" // 稳定 MP3，Telegram 也支持语音气泡
         }
       }
     }
   }
   ```
2. 重启 OpenClaw Gateway 生效：
   ```bash
   openclaw gateway restart
   ```
3. 之后 **直接发送文字回复** 即可，内置会自动附带语音气泡。切勿再手动调用 `tts` 工具，以免重复发送两条音频。

### 如果要改用 OpenAI / ElevenLabs（可选）
- 设置环境变量或在配置里填入 API key：
  - `OPENAI_API_KEY` 或 `ELEVENLABS_API_KEY`
- 然后改 `provider` 为 `openai` 或 `elevenlabs`。未配置时会自动回落到 Edge。

### 常见问题
- **为何用 MP3 也有语音气泡？** Telegram `sendVoice` 支持 OGG/Opus/MP3/M4A，OpenClaw 会按文件扩展名判断为语音消息。
- **Edge TTS OGG/Opus 失败？** 部分 `ogg-*opus` 格式 Edge 服务不支持，会回退 MP3。使用上面的 MP3 配置最稳定。
- **重复发送两条语音？** 把 `messages.tts.auto` 设为 `always` 后，不要再手动调用 `tts` 工具，只发文字即可。
