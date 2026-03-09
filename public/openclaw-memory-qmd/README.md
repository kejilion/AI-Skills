# OpenClaw 记忆后端：QMD（实验性）通用落地指南（Linux/macOS/WSL 适用）

> 目标：把 OpenClaw 的 `memory_search` 检索后端从 builtin SQLite 切换为 **QMD sidecar**，获得 **BM25（关键词）+ 向量语义 + rerank** 的混合检索质量。
>
> 事实源不变：依然是 workspace 里的 `MEMORY.md` 与 `memory/**/*.md`。
>
> 重要：QMD 在 OpenClaw 文档中标注为 **experimental**。建议按本文“灰度/可回退”方式启用。

---

## 0. 你会遇到的 3 个关键点（先看这个能少踩坑）

1) **OpenClaw 跑 QMD 时会改 XDG 目录**
- OpenClaw 会把 QMD 的 `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` 指到：
  `~/.openclaw/agents/<agentId>/qmd/xdg-config` 与 `~/.openclaw/agents/<agentId>/qmd/xdg-cache`
- 你手动运行 `qmd update/embed` 默认写到 `~/.cache/qmd/…`
- **两边不对齐**会导致：`openclaw memory status` 出现 `unable to open database file` / `Indexed: 0/...`

2) **首次 query 可能慢**
- QMD/`node-llama-cpp` 可能会首次下载 GGUF 模型（embedding/rerank/查询扩展）。

3) **Linux 上建议先强制 CPU-only（稳定优先）**
- 有些环境会误探测到 CUDA/Vulkan 痕迹，触发无意义的 GPU 构建尝试，日志很吵还可能拖慢。
- 想“先稳定跑通”，推荐设置：`NODE_LLAMA_CPP_GPU=false`。

---

## 国内环境补充建议（先看）

如果服务器在国内，建议优先阅读同仓库的 **`openclaw-memory-indexing`** 指南中的“国内环境特别说明”。

核心原则是：

- 不要赌 `hf:` 首次自动联网下载大模型文件
- 下载时可走镜像
- 运行时尽量改为本地绝对路径

也就是说：

> 镜像用于下载，运行依赖本地文件。

虽然 QMD 和 builtin local indexing 是两套后端，但“国内环境下先把模型文件本地化”这个原则是一致的。

---

## 1. 前置条件（通用）

- OpenClaw 已安装并可用（能跑 `openclaw gateway status` / `openclaw memory status`）。
- QMD CLI 需要单独安装。
- 若 `node-llama-cpp` 没有预编译包，会走源码编译：需要 **git + C/C++ 编译工具链 + cmake**。

### 1.1 安装 QMD（推荐：npm；可选：bun）

二选一即可：

**方式 A：npm（通用，推荐）**
```bash
npm i -g @tobilu/qmd
```

**方式 B：bun（官方示例）**
```bash
bun install -g https://github.com/tobi/qmd
```

验证：
```bash
qmd --help
qmd status
```

### 1.2（可选）准备编译工具链（遇到“building from source”再装）

如果你在 `qmd status` / `qmd embed` 看到类似 “falling back to building from source”，但编译失败，按发行版补齐工具链：

- Debian/Ubuntu：
```bash
apt-get update -y
apt-get install -y git build-essential cmake pkg-config
```

- RHEL/CentOS/Fedora：
```bash
dnf install -y git gcc gcc-c++ make cmake pkgconfig
```

- Alpine：
```bash
apk add --no-cache git build-base cmake pkgconf python3
```

- Arch：
```bash
pacman -Syu --noconfirm git base-devel cmake pkgconf
```

---

## 2. 在 OpenClaw 中启用 QMD backend（配置）

编辑 `~/.openclaw/openclaw.json`，加入/修改：

```json5
{
  "memory": {
    "backend": "qmd",
    "citations": "auto",
    "qmd": {
      "includeDefaultMemory": true,
      "command": "qmd",
      "searchMode": "query", // search | vsearch | query（query 质量最好但更慢）
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

重启 gateway（OpenClaw 内置命令）：
```bash
openclaw gateway restart
```

查看状态：
```bash
openclaw memory status
```

---

## 3. 关键步骤：把 QMD 索引建到 OpenClaw 使用的 XDG 目录里（通用必做）

先跑一次：
```bash
openclaw memory status
```

你会看到类似：
- `Memory Search (<agentId>)`
- `Store: ~/.openclaw/agents/<agentId>/qmd/xdg-cache/qmd/index.sqlite`

然后用下面脚本 **在同一套 XDG 目录**里建 collection/update/embed：

```bash
STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
AGENT_ID="<agentId>"   # 以 openclaw memory status 显示为准

export XDG_CONFIG_HOME="$STATE_DIR/agents/$AGENT_ID/qmd/xdg-config"
export XDG_CACHE_HOME="$STATE_DIR/agents/$AGENT_ID/qmd/xdg-cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

# （可选）稳定优先：强制 CPU-only，避免误探测 GPU 导致构建噪音
export NODE_LLAMA_CPP_GPU=false

# 建 collection（命名可自定；建议保持稳定）
qmd collection add "$STATE_DIR/workspace/memory" --name memory-root --mask "**/*.md" || true
qmd collection add "$STATE_DIR/workspace" --name memory-long --mask "MEMORY.md" || true

# 构建索引 + 向量
qmd update
qmd embed

# 冒烟检索（命中即 OK）
qmd query "JTTI" -c memory-root --json -n 3
```

完成后再次确认：
```bash
openclaw memory status
```
应看到 `Indexed: >0`。

---

## 4. Linux 通用：如何让 gateway 永久 CPU-only（按你的启动方式选一种）

> 目的：避免 node-llama-cpp 反复尝试 GPU 相关构建（尤其是在“机器装了驱动残留/库残留”时）。
> 
> 如果你明确要用 GPU（NVIDIA/CUDA 或 Vulkan），就不要设为 false。

### 4.1 systemd（OpenClaw 默认常见部署）

给 `openclaw-gateway.service` 加 drop-in：

```bash
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cat > ~/.config/systemd/user/openclaw-gateway.service.d/qmd-cpu-only.conf <<'EOF'
[Service]
Environment=NODE_LLAMA_CPP_GPU=false
EOF

systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
```

验证：
```bash
systemctl --user show openclaw-gateway.service -p Environment --value | tr ' ' '\n' | grep NODE_LLAMA_CPP_GPU
openclaw memory status
```

### 4.2 非 systemd（openrc/s6/supervisord/手动启动）

原则很简单：**让运行 gateway 的进程环境里带上**：

```bash
NODE_LLAMA_CPP_GPU=false
```

常见做法：
- 你是“手动启动 gateway”：在启动前 `export NODE_LLAMA_CPP_GPU=false`。
- 你用 supervisor：在 program 的 `environment=` 里加上它。
- 你用 openrc：在服务脚本里 export。

注意：本文不假设你的具体进程管理器，核心是“环境变量要进入 openclaw gateway 进程”。

---

## 5. 常见故障排查（最常见的 4 类）

### 5.1 `unable to open database file` / `Indexed: 0/...`
原因几乎都是 **XDG 未对齐**：你把索引建在 `~/.cache/qmd/…`，但 OpenClaw 在 `~/.openclaw/agents/<agentId>/qmd/…` 读。

处理：按本文第 3 节，用 OpenClaw 的 XDG 目录重跑一遍 `collection add` + `update` + `embed`。

### 5.2 `CUDA Toolkit not found`（或类似 GPU 构建失败）
这通常不是致命错误，但会很吵、还可能拖慢。

处理（稳定优先）：
- 设置 `NODE_LLAMA_CPP_GPU=false`（见第 4 节）。

### 5.3 首次 `qmd query` 很慢
可能在下载模型/初始化。

处理：
- 等一次完成后会明显变快；
- 先用 `qmd search`（BM25）验证链路，再跑 `qmd query`。

### 5.4 终端里出现 `EPIPE`
多见于你把输出 `| head` 截断时（管道提前关闭）。一般可忽略。

---

## 6. 重要提醒：QMD 不等于“跨天不断会话”
QMD 解决的是 **记忆检索质量**，不是 **当前会话连续性**。

很多人会遇到这样一种错觉：
- `MEMORY.md` / `memory/*.md` 都还在
- `openclaw memory status` 也正常
- 但第二天一开口，OpenClaw 像“失忆”了一样，接不上昨晚的话

这通常不是 QMD 坏了，而是 **session 重置策略**在生效。

OpenClaw 官方默认行为里，常见触发条件是：
- **daily reset**：默认按 Gateway 主机本地时间凌晨 4 点判断
- **idle reset**：默认空闲 60 分钟后过期

所以如果你没有显式配置 `session.reset` / `session.resetByType`，就可能出现：
- QMD 检索没问题
- 但会话 ID 已经换了
- 模型读不到“昨晚那一轮”的上下文

如果你希望私聊尽量跨天连续，推荐同时补上下面这套 `session` 策略：

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

一句话理解：
- **QMD**：负责把“记忆找回来”
- **session.reset**：负责让它“第二天还能接上昨天的话”

两者都要配，体验才完整。

---

## 7. 回退（安全阀）
任何时候想回 builtin：
- 删除/注释 `~/.openclaw/openclaw.json` 里的 `memory.backend = "qmd"`
- 然后：
```bash
openclaw gateway restart
```

---

## 参考
- OpenClaw Memory（QMD backend 章节）：https://docs.openclaw.ai/concepts/memory
- OpenClaw Session（会话生命周期/重置策略）：https://docs.openclaw.ai/concepts/session
- QMD 项目：https://github.com/tobi/qmd
