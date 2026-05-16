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

### [OpenAI-Compatible Image Generator](./public/openai-compatible-image-generator)
- **功能**: 调用 OpenAI 兼容的 `/v1/images/generations` 图片生成接口，支持 `gpt-image-2`、自建代理与第三方网关。
- **效果**: 内置通用 Python 脚本，自动处理 `b64_json` / `url` 返回、单图/批量输出、额外 provider 参数与密钥环境变量。
- **场景**: 快速测试图片接口、适配自定义 base URL/API key/model、把提示词生成图稳定落盘并发送附件。


### [China Stock Deep Analysis](./public/china-stock-deep-analysis)
- **功能**: 面向 A股、港股中资股、中概股 ADR 的单股深度分析、估值判断、同行对比与风险复核。
- **效果**: 自动生成小白友好的金融终端级 HTML 决策看板，可按需导出 PDF。
- **场景**: 个股研究、买卖观察框架、行业/同行比较、投资决策辅助。

### [Potential Stock Deep Screener](./public/potential-stock-deep-screener)
- **功能**: 多因子筛选中国相关潜力股，覆盖 A股、港股与中概股候选池。
- **效果**: 生成候选股排名、评分矩阵、风险热力图与漂亮 HTML 股票池看板。
- **场景**: 挖掘低估成长股、行业机会筛选、构建潜力股票池。

## 📦 如何安装

1. 克隆本仓库到你的 OpenClaw 工作区：
   ```bash
   git clone https://github.com/kejilion/AI-Skills.git
   ```
2. 在 `openclaw` 配置中引用相应的技能路径。

## 📜 开源协议

本项目采用 [MIT License](LICENSE) 开源。