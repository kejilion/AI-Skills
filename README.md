# AI-Skills

🚀 **OpenClaw Agent Skills Repository**

这里存放着为 OpenClaw 助手量身定制的各项技能（Skills）。通过这些技能，AI 助理可以像人类一样操作复杂的 Web 界面、处理多媒体资源以及执行特定的自动化流。

## 🛠️ 当前包含的技能

### [OpenClaw Memory Indexing (SQLite + Local Embedding)](./public/openclaw-memory-indexing)
- **功能**: 在本地启用 OpenClaw 记忆索引（SQLite + 向量检索），并提供最稳的升级/备份实践。
- **场景**: 频繁升级 OpenClaw 也不易“失忆”，索引坏了可重建，源数据可审计。

### [OpenClaw Memory Backend: QMD (Hybrid Search + Rerank)](./public/openclaw-memory-qmd)
- **功能**: 将 OpenClaw 的记忆检索后端切换为 QMD（BM25 + 向量 + rerank），提供落地/灰度/回退指南。
- **场景**: 记忆库变大后追求更强召回与排序质量；可选增强（experimental）。

### [Telegram Voice TTS (Edge-TTS + FFmpeg)](./public/telegram-voice-tts)
- **功能**: 生成符合 Telegram 原生规范的蓝色语音条。
- **效果**: 调用 Microsoft Edge TTS 生成高保真语音（默认云扬男声），并自动通过 FFmpeg 压制为 OGG/Opus 编码格式。
- **场景**: 告别机械的 MP3 文件传输，让 AI 助手在 Telegram 中以人类般的“语音泡泡”进行回复。

### [Video Talk Editor (Silent Trimming)](./public/video-talk-editor)
- **功能**: 智能视频剪辑，自动去除谈话类视频中的静音片段。
- **效果**: 结合 `faster-whisper` 精准定位人声，通过 `ffmpeg` 自动切除停顿与空白，并可选生成压缩版高能视频。
- **场景**: 极大地提升视频后期效率，让视频内容更紧凑、更有表现力，特别适合 Vlog、教程或会议记录。

### [HuggingFace Multi-View Generator (Qwen)](./public/hf-multiview-qwen)
- **功能**: 自动调用 HuggingFace/ModelScope 上的 Qwen 3D 摄影机模型。
- **效果**: 只需一张原图，即可自动生成：正视、侧视、背视、顶视、45度斜视五张高保真照片。
- **场景**: 适用于电商产品展示、3D 建模参考、解锁 Netflix/游戏加速等场景的视觉素材生成。

## 📦 如何安装

1. 克隆本仓库到你的 OpenClaw 工作区：
   ```bash
   git clone https://github.com/kejilion/AI-Skills.git
   ```
2. 在 `openclaw` 配置中引用相应的技能路径。

## 📜 开源协议

本项目采用 [MIT License](LICENSE) 开源。