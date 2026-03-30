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

> ⚠️ **重要**：Edge TTS 在 OpenClaw 内部的 provider id 是 `microsoft`（非 `edge`）。
> 顶层 `provider` 可以写 `"edge"`（会自动映射），但 `providers` 下的配置 key **必须用 `microsoft`**，否则 voice/lang 等参数不会生效，会回退到默认英文音色 `en-US-MichelleNeural`。

#### 方法一：命令行配置（推荐）
```bash
openclaw config set messages.tts.auto always
openclaw config set messages.tts.provider edge
openclaw config set messages.tts.providers.microsoft.enabled true
openclaw config set messages.tts.providers.microsoft.voice "zh-CN-YunyangNeural"
openclaw config set messages.tts.providers.microsoft.lang "zh-CN"
openclaw config set messages.tts.providers.microsoft.outputFormat "audio-24khz-48kbitrate-mono-mp3"
openclaw gateway restart
```

#### 方法二：手动编辑配置文件
编辑 `/root/.openclaw/openclaw.json`（或对应主机配置），在 `messages.tts` 下设置：
```json5
{
  "messages": {
    "tts": {
      "auto": "always",              // 每条回复都带语音
      "provider": "edge",             // 使用 Edge TTS（无密钥）
      "providers": {
        "microsoft": {                // ⚠️ 必须用 "microsoft"，不能用 "edge"
          "enabled": true,
          "voice": "zh-CN-YunyangNeural",   // 中文男声（云阳）
          "lang": "zh-CN",
          "outputFormat": "audio-24khz-48kbitrate-mono-mp3"
        }
      }
    }
  }
}
```
然后重启 Gateway：
```bash
openclaw gateway restart
```

之后 **直接发送文字回复** 即可，内置会自动附带语音气泡。切勿再手动调用 `tts` 工具，以免重复发送两条音频。

### 常见中文音色

| Voice ID | 性别 | 风格 |
|---|---|---|
| `zh-CN-YunyangNeural` | 男 | 新闻播报、沉稳 |
| `zh-CN-XiaoxiaoNeural` | 女 | 温暖、日常 |
| `zh-CN-YunxiNeural` | 男 | 年轻、活力 |
| `zh-CN-XiaoyiNeural` | 女 | 活泼、轻快 |

完整列表：`edge-tts --list-voices | grep zh-CN`

### 如果要改用 OpenAI / ElevenLabs（可选）
- 设置环境变量或在配置里填入 API key：
  - `OPENAI_API_KEY` 或 `ELEVENLABS_API_KEY`
- 然后改 `provider` 为 `openai` 或 `elevenlabs`。未配置时会自动回落到 Edge。

### 常见问题
- **语音是英文？** 检查配置 key 是否写成了 `providers.edge`——必须是 `providers.microsoft`。OpenClaw 内部 Edge TTS 注册为 `microsoft` provider。
- **为何用 MP3 也有语音气泡？** Telegram `sendVoice` 支持 OGG/Opus/MP3/M4A，OpenClaw 会按文件扩展名判断为语音消息。
- **Edge TTS OGG/Opus 失败？** 部分 `ogg-*opus` 格式 Edge 服务不支持，会回退 MP3。使用上面的 MP3 配置最稳定。
- **重复发送两条语音？** 把 `messages.tts.auto` 设为 `always` 后，不要再手动调用 `tts` 工具，只发文字即可。
