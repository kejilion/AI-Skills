# OpenClaw 记忆（Memory）索引：最稳本地方案（SQLite + 本地 Embedding）

> 目标：即使频繁升级 OpenClaw，也不“失忆”。
>
> 核心原则：**Markdown 是事实源；SQLite 只是索引缓存。**
> - `MEMORY.md` / `memory/**/*.md` 永远可读、可备份、可审计。
> - SQLite 索引坏了随时 `openclaw memory index` 重建。

---

## 1. 目录与文件（推荐结构）
在 OpenClaw workspace 下维护：

```text
workspace/
  MEMORY.md
  BOOTSTRAP.md
  memory/
    WORKFLOWS/
    INFRA/
    2026-03-04.md
  PRIVATE/            # 敏感信息（不建议纳入公开索引）
  scripts/
    backup_memories.sh
  backups/
    memory-backup-YYYYmmdd-HHMMSS.tar.gz
```

### 为什么这样最稳？
- **事实源**在 Markdown（不依赖任何 DB/向量库）。
- 索引只是加速检索，坏了可重建。
- `PRIVATE/` 用于隔离密码、应用密码等敏感内容，避免误泄露。

---

## 2. 启用本地记忆索引（Local Embedding）
适用场景：
- 不想依赖外网 API（embedding provider）
- 希望升级后仍可用

### 2.1 修改配置（openclaw.json）
编辑：`~/.openclaw/openclaw.json`

在 `agents.defaults.memorySearch` 下配置：

```json5
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "local",
        "fallback": "none",
        "sync": { "watch": true },
        "local": {
          // 官方推荐默认：embeddinggemma 300M（约 0.6GB）
          "modelPath": "hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf"
        },
        "store": {
          "path": "~/.openclaw/memory/{agentId}.sqlite"
        }
      }
    }
  }
}
```

> 说明
> - 首次索引会自动下载 embedding 模型（约 0.6GB）。
> - `watch: true` 表示监听文件变更（但不保证每次编辑都立即重建索引，见“实时性”章节）。

### 2.2 重启 Gateway
```bash
openclaw gateway restart
```

### 2.3 建索引
```bash
openclaw memory index
```

### 2.4 查看状态
```bash
openclaw memory status
```

看到类似信息即正常：
- `Provider: local`
- `Vector: ready`
- `Indexed: ... chunks`

---

## 3. 实时性：索引是否“实时增量”？
结论：**源文件写入是实时的；索引更像异步/按需更新**。

建议最佳实践：
- 每次“重要信息写入/更新”后，手动跑一次：
  ```bash
  openclaw memory index
  ```
- 把这一步写入你的工作流（或用定时任务每天跑）。

---

## 4. 升级/崩溃不失忆（最稳）
### 4.1 必须备份的“真记忆”（事实源）
- `MEMORY.md`
- `BOOTSTRAP.md`
- `memory/`
- `PRIVATE/`
- `~/.openclaw/openclaw.json`

### 4.2 可重建的索引（缓存）
- `~/.openclaw/memory/*.sqlite`

索引坏了：
```bash
openclaw memory index
```

---

## 5. 一键备份脚本（推荐）
创建：`workspace/scripts/backup_memories.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TS=$(date +"%Y%m%d-%H%M%S")
OUT_DIR="backups"
OUT="$OUT_DIR/memory-backup-$TS.tar.gz"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR" || true

tar -czf "$OUT" \
  MEMORY.md \
  BOOTSTRAP.md \
  memory \
  PRIVATE \
  ~/.openclaw/openclaw.json

# 保留最近 30 份
ls -1t "$OUT_DIR"/memory-backup-*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm -f

echo "OK: $OUT"
```

执行：
```bash
bash scripts/backup_memories.sh
```

建议：每次升级 OpenClaw 前先跑一次。

---

## 6. 常见问题
### Q1：本地 embedding 模型多大？
- `embeddinggemma-300M` 约 **0.6GB**（官方推荐默认）。

### Q2：向量检索启用后就不会忘了吗？
- 它能显著提升“检索能力”，但前提是：**你要把关键事实写进 Markdown 记忆文件**。

### Q3：敏感信息怎么办？
- 放 `PRIVATE/`，并在对外的 SOP/记忆中只写“入口”，不写密码。

---

## 7. 建议的最小落地清单
- [ ] 建立 `MEMORY.md` + `BOOTSTRAP.md` + `memory/` 结构
- [ ] 配置 `memorySearch.provider=local`
- [ ] 首次运行 `openclaw memory index`
- [ ] 每次升级前跑 `backup_memories.sh`
