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
- 推荐使用 Bun 全局安装（或下载 release）。

2) **SQLite 需允许加载 extensions**
- QMD 依赖 sqlite 扩展能力（不同发行版的 sqlite 构建策略不同）。

3) **本地模型运行环境**
- QMD 通过 Bun + `node-llama-cpp` 本地运行，并在首次使用时自动下载 GGUF 模型（embedding/rerank/查询扩展）。

> 资源提醒：QMD 比 builtin memorySearch 更“重”，首次查询可能会下载模型并变慢。

---

## 2. 最小可行性验证（推荐先做）
在你切换 OpenClaw 配置之前，先确保 QMD 在系统上能跑通：

1) 确认 `qmd` 可执行：
```bash
qmd --help
```

2) 给记忆目录建 collection（示例）：
```bash
qmd collection add ~/.openclaw/workspace/memory --name memory
qmd collection add ~/.openclaw/workspace --name workspace --pattern "**/*.md"
```

3) 更新索引 + 生成 embedding：
```bash
qmd update
qmd embed
```

4) 试一次混合检索（质量最好）：
```bash
qmd query "测试" --json -n 5
```

如果以上步骤能返回结果，说明 QMD 侧链路没问题。

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
      "searchMode": "search", // 可选：search | vsearch | query（query 通常质量最好但更慢）
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
理想状态会显示 backend 为 qmd（若 OpenClaw 有暴露该字段）。

---

## 4. 预热/首次查询变慢怎么办？
官方文档提示：首次 `qmd query` 可能会下载 GGUF 模型并较慢。

你可以在切换前先“手动预热一次”，或者按 OpenClaw 文档导出的 XDG 目录对齐方式预热 QMD（确保用的是 OpenClaw 预期的 QMD home）。

---

## 5. 与我们现有方案的对比（什么时候值得上）

### 继续用 builtin（SQLite + 本地 embedding）更合适：
- 你更在意稳定、少依赖、升级省心
- 记忆规模不大
- 当前检索准确率已够用

### 上 QMD 更合适：
- 你要更强的“混合检索 + rerank”质量
- 你能接受额外依赖（Bun/QMD/SQLite 扩展）
- 你愿意做一次落地验证与灰度切换

---

## 6. 回退策略（必备）
如果你发现 QMD 不稳定或环境不适配：
- 删除/注释 `memory.backend = "qmd"`
- 回到 builtin memorySearch（SQLite）
- 重新 `openclaw gateway restart`

---

## 7. 推荐落地路径（最稳）
1) 先保持 builtin memorySearch（我们已验证可用）
2) 装 Bun/QMD/SQLite 并跑通“最小可行性验证”
3) 再灰度切换 `memory.backend=qmd`（一两天观察）
4) 发现问题随时回退

---

## 参考
- OpenClaw Memory 文档（QMD backend）：https://docs.openclaw.ai/concepts/memory
- QMD 项目：https://github.com/tobi/qmd
