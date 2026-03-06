# 飞书（Feishu）对接指南 - OpenClaw

本指南说明如何在 OpenClaw 中启用飞书渠道，并进行快速校验与重启。

## 1. 配置文件位置
- 路径：`~/.openclaw/openclaw.json`

## 2. 正确配置结构（示例）
> 注意：下方为结构示例，请替换为你自己的真实 AppID/Secret；请勿将真实密钥入库。

```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "accounts": {
        "main": {
          "appId": "REPLACE_WITH_YOUR_APP_ID",
          "appSecret": "REPLACE_WITH_YOUR_APP_SECRET"
        }
      }
    }
  }
}
```

## 3. 关键点
- 配置位于 `channels` 下（不是 `plugins`）。
- 字段名为 `appId` 与 `appSecret`（驼峰命名）。
- 必须包含 `accounts` 结构，且默认使用 `main` 账户。

## 4. 重启服务
```bash
openclaw gateway restart
```

## 5. 快速校验
- 结构检查（需要安装 jq）：
```bash
jq -e '.channels.feishu.enabled == true and .channels.feishu.accounts.main.appId and .channels.feishu.accounts.main.appSecret' ~/.openclaw/openclaw.json && echo OK || echo FAIL
```

- 若需要简单脱敏（就地将值替换为占位符，自动备份为 .bak）：
```bash
sed -i.bak -E \
  's/("appId"[[:space:]]*:[[:space:]]*")([^"]+)(")/\1REDACTED_APP_ID\3/g; \
   s/("appSecret"[[:space:]]*:[[:space:]]*")([^"]+)(")/\1REDACTED_APP_SECRET\3/g' \
  ~/.openclaw/openclaw.json
```

## 6. 安全与版本控制
- 切勿把真实 `appId`/`appSecret` 提交到 Git 仓库。
- 如需提交样例，请使用上述“脱敏”命令处理后再提交。

## 7. 常见问题
- 启用后无响应：请确认已 `openclaw gateway restart`，并查看 `openclaw gateway status`。
- 校验失败：检查 JSON 结构是否严格遵循示例（键名大小写、嵌套层级）。

---

# 📝 飞书对接问题解决经验（代理/WAF 相关）

## 🔍 问题现象
1. 飞书渠道配置显示 OK，但消息不通
2. 日志反复出现 `400 The plain HTTP request was sent to HTTPS port`
3. WebSocket 多次重连失败

## 🎯 根本原因
系统或服务层设置了 HTTP/HTTPS 代理，导致飞书 API/WS 请求被错误转发：
- HTTP 被代理到 HTTPS 端口
- SDK 鉴权失败
- WS 握手失败

## 💡 诊断步骤
1. 基础检查：`openclaw gateway status`、插件启用、配置完整性
2. 直连验证：`curl` 调飞书 API（若成功，证明凭证有效）
3. 日志研判：关注 `400`、`socket hang up`、`ws reconnecting`
4. 环境排查：`env | grep -i proxy`，确认是否设置代理环境变量
5. 服务配置：检查 systemd 用户服务是否硬编码代理

## 🛠 处理方案
编辑并移除用户服务中的代理变量：

`~/.config/systemd/user/openclaw-gateway.service`
删除以下行：
```
Environment=HTTP_PROXY=http://127.0.0.1:10770
Environment=HTTPS_PROXY=http://127.0.0.1:10770
Environment=http_proxy=http://127.0.0.1:10770
Environment=https_proxy=http://127.0.0.1:10770
# 以及 NO_PROXY 相关行（如有）
```
重载并重启：
```bash
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway
```

## 📊 验证标准
- 日志不再出现 `400` 错误
- 飞书 bot open_id 解析成功
- `ws client ready` 出现
- `openclaw status` 显示飞书渠道 OK

## 🧠 经验教训
- 代理隐蔽性强：curl 直连成功不代表服务进程未走代理
- 服务优先级：systemd 服务里的环境变量优先于 shell
- 错误解码：`400 The plain HTTP request was sent to HTTPS port` 常见于错误代理
- 分层排查：网络 → API → 应用 → 服务配置

## 🔧 预防建议
- 统一代理管理，明确哪些服务需直连
- 审核服务文件中的环境变量
- 对关键错误做日志监控与告警
- 新环境上线前做端到端收发验证
