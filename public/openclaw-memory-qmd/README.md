# OpenClaw 记忆后端：QMD（实验性）落地指南（本地混合检索 + rerank）

> 适用：你想把 OpenClaw 的 `memory_search` 从内置 SQLite 向量索引切换到 **QMD sidecar**。
>
> 目标：**BM25（关键词）+ 向量语义 + reranking** 的混合检索，仍保持 **Markdown 为事实源**。
>
> 注意：QMD 是 OpenClaw 文档里标注的 **experimental** 方案。建议先灰度验证，确保可随时回退。

---

## 0. 核心概念（必须先搞清）
- **事实源不变**：仍是 workspace 下的 `MEMORY.md` 与 `memory/**/*.md`。
- **变化的是检索引擎**：
  - 默认：OpenClaw builtin（SQLite + sqlite-vec + embeddings）
  - 切换后：OpenClaw 调用 `qmd` CLI 做检索（QMD 自己维护索引与模型）。
- **可回退**：QMD 缺失/异常时，OpenClaw 会自动回落到 builtin memory manager（保证 memory 工具不至于完全不可用）。

---

## 1. 前置条件（Prereqs）
根据 OpenClaw 官方文档（concepts/memory → QMD backend）：

1) **安装 QMD CLI**（OpenClaw 不会替你装）
- 官方示例偏 Bun：`bun install -g https://github.com/tobi/qmd`
- **实测：也可以用 npm 安装（更通用）**：`npm i -g @tobilu/qmd`

2) **SQLite 需允许加载 extensions**
- QMD 依赖 sqlite 扩展能力（不同发行版的 sqlite 构建策略不同）。

3) **本地模型运行环境**
- QMD 通过 `node-llama-cpp` 本地运行，并在首次使用时自动下载 GGUF 模型（embedding/rerank/查询扩展）。

> 资源提醒：QMD 比 builtin memorySearch 更“重”，首次查询可能会下载模型并变慢。

---

## 2. 最小可行性验证（先跑通 QMD）
在你切换 OpenClaw 配置之前，先确保 QMD 在系统上能跑通：

1) 确认 `qmd` 可执行：
```bash
qmd --help
qmd status
```

2) 给记忆目录建 collection（示例）
> 注意：不同版本参数名可能不同。本指南以 `qmd --help` 输出为准（实测是 `--mask`）。

```bash
# 索引 daily memory
qmd collection add ~/.openclaw/workspace/memory --name memory --mask "**/*.md"

# 索引长期 MEMORY.md（只索引该文件即可）
qmd collection add ~/.openclaw/workspace --name memory-long --mask "MEMORY.md"
```

3) 更新索引 + 生成 embedding：
```bash
qmd update
qmd embed
```

4) 试一次混合检索（质量最好但更慢）：
```bash
qmd query "测试" --json -n 5
```

如果以上步骤能返回结果，说明 **QMD 本体链路**没问题。

---

## 3. 在 OpenClaw 中启用 QMD backend
编辑 `~/.openclaw/openclaw.json`，加入/修改 `memory`：

```json5
{
  "memory": {
    "backend": "qmd",
    "citations": "auto",
    "qmd": {
      "includeDefaultMemory": true,
      "command": "qmd",
      "searchMode": "query", // search | vsearch | query（query 通常质量最好但更慢）
      "update": {
        "interval": "5m",
        "debounceMs": 15000,
        "onBoot": true,
        "waitForBootSync": false
      },
      "limits": {
        "maxResults": 6,
        "timeoutMs": 4000
      },
      "paths": [
        // 可选：额外索引目录
        { "name": "docs", "path": "~/notes", "pattern": "**/*.md" }
      ],
      "scope": {
        "default": "deny",
        "rules": [
          { "action": "allow", "match": { "chatType": "direct" } }
        ]
      }
    }
  }
}
```

重启 gateway：
```bash
openclaw gateway restart
```

诊断：
```bash
openclaw memory status
```

---

## 4. 关键踩坑（必看）：OpenClaw 的 QMD 索引目录（XDG）要对齐
OpenClaw 在运行 QMD 时，会把 QMD 的 `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` 指向：

- `~/.openclaw/agents/<agentId>/qmd/xdg-config`
- `~/.openclaw/agents/<agentId>/qmd/xdg-cache`

也就是说：
- 你在 shell 里直接跑 `qmd update/embed`，默认索引会建在 `~/.cache/qmd/index.sqlite`
- 但 OpenClaw 期望的索引在 `~/.openclaw/agents/<agentId>/qmd/xdg-cache/qmd/index.sqlite`

如果不对齐，会出现典型错误：
- `openclaw memory status` 警告：`failed to read qmd index stats: unable to open database file`
- 或者显示 `Indexed: 0/...`

### 4.1 一键在 OpenClaw 的 XDG 目录下重建索引（推荐做法）
先从 `openclaw memory status` 里确认你的 `<agentId>`（以及 Store 路径）。

然后运行：
```bash
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
AGENT_ID="<agentId>"  # 例如：main / expert-4.6（以 openclaw memory status 为准）

export XDG_CONFIG_HOME="$STATE_DIR/agents/$AGENT_ID/qmd/xdg-config"
export XDG_CACHE_HOME="$STATE_DIR/agents/$AGENT_ID/qmd/xdg-cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# 建 collection（命名可自定；建议跟 OpenClaw 逻辑一致）
qmd collection add ~/.openclaw/workspace/memory --name memory-root --mask "**/*.md" || true
qmd collection add ~/.openclaw/workspace --name memory-long --mask "MEMORY.md" || true

# 构建索引 + 向量
qmd update
qmd embed

# 试一次检索
qmd query "JTTI" -c memory-root --json -n 3
```

完成后，`openclaw memory status` 应该能看到非 0 的 Indexed。

---

## 5. Debian/arm64 实测补丁：强制 CPU-only（避免 CUDA 反复报错/尝试构建）
在 Linux（尤其 arm64）上，`node-llama-cpp` 可能会错误地检测到 CUDA 相关库痕迹，然后尝试构建 CUDA 变体并失败（日志很吵、还可能拖慢首次运行）。

推荐做法：给 OpenClaw gateway 的 systemd service 加 drop-in，强制 CPU-only：

```bash
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cat > ~/.config/systemd/user/openclaw-gateway.service.d/qmd-cpu-only.conf <<'EOF'
[Service]
Environment=NODE_LLAMA_CPP_GPU=false
EOF

systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
```

验证（环境变量生效 + QMD backend 正常）：
```bash
systemctl --user show openclaw-gateway.service -p Environment --value | tr ' ' '\n' | grep NODE_LLAMA_CPP_GPU
openclaw memory status
```

---

## 6. 回退策略（必备）
如果你发现 QMD 不稳定或环境不适配：
- 删除/注释 `memory.backend = "qmd"`
- 回到 builtin memorySearch（SQLite）
- `openclaw gateway restart`

---

## 参考
- OpenClaw Memory 文档（QMD backend）：https://docs.openclaw.ai/concepts/memory
- QMD 项目：https://github.com/tobi/qmd
