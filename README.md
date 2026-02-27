# AI-Skills

🚀 **OpenClaw Agent Skills Repository**

这里存放着为 OpenClaw 助手量身定制的各项技能（Skills）。通过这些技能，AI 助理可以像人类一样操作复杂的 Web 界面、处理多媒体资源以及执行特定的自动化流。

## 🛠️ 当前包含的技能

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
