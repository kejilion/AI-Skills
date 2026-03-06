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
