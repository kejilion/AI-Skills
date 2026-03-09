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


## 2.5 国内环境特别说明（强烈建议看）

在国内环境下，**不要依赖 Hugging Face 官方源自动下载本地 embedding 模型**。

最稳方案是：

1. 先从国内可达镜像把 GGUF 模型手动下载到本地
2. 在 `openclaw.json` 中把 `memorySearch.local.modelPath` 指向本地绝对路径
3. 手动执行索引重建并检查状态

一句话：

> 下载时走镜像，运行时走本地路径。

### 为什么这一步很关键？

很多时候你会看到：

- `Provider: local`
- `Vector: ready`
- `FTS: ready`

但继续看会发现：

- `Indexed: 0/x files · 0 chunks`

这说明：

- SQLite/FTS 可能已经初始化完成
- 向量扩展也可能可用
- 但 embedding 阶段并没有真正跑通

所以：

> `Provider: local` 不等于索引已经真正可用。

### 国内环境下的典型根因

如果你使用的是这种配置：

```json5
"modelPath": "hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf"
```

而服务器对 `huggingface.co` 官方源不可达，就容易出现：

- `openclaw memory index` 长时间转圈
- `memory_search` 超时或失败
- 日志里出现 `memory embeddings batch timed out after 600s`、`fetch failed` 一类错误

### 推荐做法：手动下载模型到本地

先创建本地目录：

```bash
mkdir -p ~/.openclaw/models
```

然后从国内可达镜像下载模型：

```bash
curl -L -o ~/.openclaw/models/embeddinggemma-300M-Q8_0.gguf \
  "https://hf-mirror.com/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf"
```

如果没有 `curl`，也可以用：

```bash
wget -O ~/.openclaw/models/embeddinggemma-300M-Q8_0.gguf \
  "https://hf-mirror.com/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf"
```

### 配置本地模型路径

编辑 `~/.openclaw/openclaw.json`，把 `modelPath` 改成**本地绝对路径**：

```json5
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "local",
        "fallback": "none",
        "local": {
          "modelPath": "/root/.openclaw/models/embeddinggemma-300M-Q8_0.gguf"
        }
      }
    }
  }
}
```

注意：

- 建议写**本地绝对路径**
- 不要继续依赖 `hf:` URI 让它首次自动联网下载

### 然后强制重建索引

```bash
openclaw memory index --force
openclaw memory status
```

### 真正要看什么才算成功？

不要只看：

- `Provider: local`
- `Vector: ready`

真正要看的是：

- `Indexed: x/x files`
- `chunks > 0`

例如：

```text
Indexed: 4/4 files · 6 chunks
Dirty: no
Vector: ready
FTS: ready
```

看到这种，才说明本地记忆索引真的可用了。

### 推荐排查顺序

如果以后再次遇到本地记忆索引失败，建议按这个顺序查：

1. `openclaw memory status`
2. 如果 `Indexed = 0`，优先怀疑模型文件不存在、`modelPath` 错误、`hf:` 自动下载失败、embedding 阶段超时
3. `ls -lh ~/.openclaw/models/` 确认模型文件真实存在
4. 如果官方源不可达，优先切换镜像
5. `openclaw memory index --force` 强制重建

### 国内环境最佳实践

- 服务器在国内时，embedding 模型优先本地化
- 升级前建议备份：`MEMORY.md`、`memory/*.md`、`~/.openclaw/openclaw.json`、`~/.openclaw/models/*.gguf`、`~/.openclaw/memory/*.sqlite`
- 镜像只是下载手段，不是长期依赖点；**下载走镜像，运行走本地文件**

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

## 7. 为什么明明记忆文件还在，第二天却像“失忆”了？
这是一个非常常见的误区。

很多人会以为：
- `MEMORY.md` 还在
- `memory/*.md` 也都没丢
- SQLite 索引也正常

那 OpenClaw 第二天就应该还能顺着昨晚的话继续聊。

但实际上，**记忆文件/索引** 和 **会话连续性** 是两件事：

- `MEMORY.md` / `memory/**/*.md`：负责“事实有没有被写下来”
- SQLite / embedding 索引：负责“这些事实能不能被检索出来”
- `session.reset`：负责“当前聊天能不能继续沿用昨晚那个 sessionId”

如果你没有显式配置 `session.reset` / `resetByType`，OpenClaw 很可能会落回默认策略：
- **daily reset**：默认按 Gateway 主机本地时间凌晨 4 点
- **idle reset**：默认空闲 60 分钟

这就会出现一个典型现象：
- 记忆文件没丢
- 索引也没坏
- 但会话已经换了
- 所以它“看起来像失忆”

### 推荐一起补上的 session 策略
如果你希望私聊尽量跨天连续，而群聊不要拖太长上下文，可以在 `~/.openclaw/openclaw.json` 里加上：

```json5
{
  session: {
    dmScope: "per-channel-peer",
    resetTriggers: ["/new", "/reset"],
    reset: {
      mode: "idle",
      idleMinutes: 10080 // 7 天
    },
    resetByType: {
      direct: { mode: "idle", idleMinutes: 10080 },
      thread: { mode: "idle", idleMinutes: 1440 },
      group: { mode: "idle", idleMinutes: 120 }
    }
  }
}
```

### 怎么理解这套配置？
- **私聊（direct）**：最需要跨天连续，给 7 天 idle 比较合适
- **线程 / Telegram topic / Discord thread**：更像围绕任务的上下文，1 天 idle 重置更合理
- **群聊（group）**：噪音最大，2 小时已经足够保守

一句话总结：
- **本篇记忆索引方案**：保证“记忆事实不会丢，索引坏了也能重建”
- **session.reset 策略**：保证“它第二天不至于像完全没聊过”

两者一起配，体验才完整。

---

## 8. 建议的最小落地清单
- [ ] 建立 `MEMORY.md` + `BOOTSTRAP.md` + `memory/` 结构
- [ ] 配置 `memorySearch.provider=local`
- [ ] 首次运行 `openclaw memory index`
- [ ] 同时补上 `session.reset` / `resetByType` 策略
- [ ] 每次升级前跑 `backup_memories.sh`
