# cc-notify

> **AI 写代码时，一旦需要你介入，立刻通知你**。默认优先覆盖“需要人回来处理”的场景，尽量减少把过程态误报成终态。

[![macOS](https://img.shields.io/badge/platform-macos-lightgrey)](https://www.apple.com/macos)
[![Bark](https://img.shields.io/badge/push-Bark-green)](https://github.com/Finb/Bark)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## 为什么需要它

在 AI Coding 里，模型经常需要你**当场介入**：

- 要执行命令 / 改文件，等你点「允许」
- 问你「用 A 还是 B」，等你选
- 要你补充信息、登录、填写表单
- 真正卡住或结束时，需要你回来处理

如果你这时在查文档、开会或锁屏，**你根本不知道**，AI 在那边空等，你也白白浪费时间。
**cc-notify** 会在这些「需要人介入」的时刻，把通知推到你的手机，让你马上回来处理，而不是事后才发现卡住了。

## 核心理念

```
需要你确认/选择/处理 → 尽快通知（高优先级，短延迟即发）
任务完成但你人不在 → 通知你（锁屏/切走才发，避免刷屏）
你正盯着终端看     → 不打扰（你已经看到了）
```

## 支持的工具

| 工具 | 状态 | 默认通知策略 |
|-----|------|-------------|
| Claude Code | ✅ | 精确监听权限确认、等待输入、Elicitation、真正终止失败 |
| Cursor | ✅ | 轻量支持，默认只监听 `stop`，避免 Shell 过程噪音 |
| OpenCode | ✅ | 使用官方插件机制监听 `permission.asked` / `session.error` / `session.idle` |
| Codex | ✅ | 使用官方实验 hooks；对 `Stop` 做“是否在等你回复”的启发式识别，并监听 Bash 后的人工可处理错误 |
| 其他工具 | ✅ | 可通过统一 CLI 参数接入 |

## 快速开始

### 1. 前置要求

- macOS（锁屏检测、前台应用检测依赖 macOS）
- [Bark App](https://apps.apple.com/app/bark/id1403753865)（iOS 通知推送）
- jq：`brew install jq`

### 2. 安装

**方式一：curl 一键安装（推荐）**

```bash
curl -fsSL https://raw.githubusercontent.com/USER/cc-notify/main/install.sh | bash
```

发布到 GitHub 后，将上面的 `USER/cc-notify` 替换成你的实际仓库地址即可。

**方式二：本地安装**

```bash
git clone https://github.com/USER/cc-notify.git
cd cc-notify
./install.sh
```

### 3. 配置 Bark

1. 在 iPhone 上安装 [Bark](https://apps.apple.com/app/bark/id1403753865)
2. 打开 Bark，复制你的 Key
3. 安装时按提示输入 Key，或预先设置：`export BARK_KEY=你的BarkKey`

### 4. 授权

首次使用需在 **系统设置 → 隐私与安全 → 辅助功能** 中授权终端应用（用于判断你是否正在看终端，避免重复打扰）。

## 安装界面

安装脚本会自动检测已安装的 AI 工具，并提供交互式多选界面：

```
╔──────────────────────────────────────╗
│  🚀 cc-notify 智能通知系统           │
╚──────────────────────────────────────╝

━━━ [1/6] 检查依赖
✅ 依赖完整

━━━ [2/6] 检测已安装的 AI 工具

  ✅ Claude Code   ~/.claude/settings.json
  ✅ Cursor        ~/.cursor/hooks.json
  ✅ Codex         ~/.codex/hooks.json
  ⚠️  OpenCode     (未安装)

━━━ [3/6] 配置 Bark 通知
...
```

**提示**：如果安装了 `fzf` 或 `gum`，会获得更好的交互体验。

## 典型场景

### 需要你确认时 → 马上通知

```
1. Claude: "要执行 npm install 吗？" / "用 React 还是 Vue？"
2. 你在浏览器查资料，没看终端
3. 几秒内 → 手机收到「需要确认」通知
4. 你点开，做出选择，AI 继续跑
```

### 真正需要你回来处理 → 通知你回来

```
1. 终端: claude "帮我修这个 bug"
2. 你锁屏去开会
3. Claude 弹出权限确认 / 登录 / 等待你补充信息
4. 手机收到通知 → 你知道该回来处理了
```

### 你正盯着终端 → 不打扰

```
1. 你一直在看终端
2. 任务完成或需要确认
3. 不发送通知（避免重复打扰）
```

## 通知优先级（何时发、多快发）

| 优先级 | 触发场景 | 行为 |
|-------|----------|------|
| **高** | 权限确认、等待输入、Elicitation、明确需要人工处理的错误 | 短延迟后重检，确认你已离开再发 |
| **中** | 任务完成、真正停止失败 | 锁屏或切走时发送 |
| **低** | 会话结束、工具停止 | 仅在你离开时发送 |

## 目录结构

```
cc-notify/
├── install.sh              # 一键安装入口
├── lib/
│   ├── common.sh           # 公共函数（交互、日志等）
│   ├── detect.sh           # 工具检测
│   ├── configure.sh        # 配置合并
│   └── notify.sh           # 核心通知脚本
├── templates/
│   ├── claude-hooks.json   # Claude Code hooks
│   ├── cursor-hooks.json   # Cursor hooks
│   ├── codex-hooks.json    # Codex hooks
│   └── opencode-plugin.js  # OpenCode 官方插件
├── doc/
│   └── AI-Coding-智能通知系统-最终版.md
├── CHANGELOG.md
└── README.md
```

## 配置文件

| 文件 | 路径 | 合并策略 |
|-----|------|---------|
| 用户配置 | `~/.cc-notify/config.json` | 保留现有配置 |
| 通知脚本 | `~/.cc-notify/bin/smart-notify.sh` | 覆盖更新 |
| Claude Code | `~/.claude/settings.json` | 升级 cc-notify 管理的 hooks，保留用户自定义 hooks |
| Cursor | `~/.cursor/hooks.json` | 升级 cc-notify 管理的 hooks，保留用户自定义 hooks |
| Codex hooks | `~/.codex/hooks.json` | 升级 cc-notify 管理的 hooks，保留用户自定义 hooks |
| Codex feature | `~/.codex/config.toml` | 自动启用 `codex_hooks = true` |
| OpenCode 插件 | `~/.config/opencode/plugins/cc-notify.js` | 覆盖更新官方插件文件 |
| OpenCode 旧配置 | `~/.config/opencode/opencode.json` | 清理旧版 cc-notify 遗留 hooks，保留其他字段 |

**重要**：安装时会自动备份原有配置文件（`.bak.时间戳`），并会替换旧版 cc-notify 自己写入的 hook，避免历史误配置一直残留。

## 测试

```bash
# 普通通知
~/.cc-notify/bin/smart-notify.sh "测试" "安装成功" "normal"

# 高优先级（短延迟后重检，模拟「需要介入」）
~/.cc-notify/bin/smart-notify.sh "测试" "需要确认" "high"

# 低优先级
~/.cc-notify/bin/smart-notify.sh "测试" "低优先级" "low"

# 干跑模式（不真的调用 Bark，方便调试事件分类）
printf '%s' '{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"请补充部署环境信息"}' \
  | CC_NOTIFY_DRY_RUN=1 CC_NOTIFY_FORCE_NOTIFY=1 \
    ~/.cc-notify/bin/smart-notify.sh --source claude-code

# 调试模式（显示详细日志）
CC_NOTIFY_DEBUG=1 ~/.cc-notify/bin/smart-notify.sh "测试" "调试" "normal"
```

## Claude Code 默认事件

默认模板不再把 `Stop` 当成“任务完成”，也不再把所有 `PostToolUseFailure` 都当成需要你立刻处理的错误。现在默认监听的是：

- `PermissionRequest`：需要你授权继续
- `Notification(idle_prompt)`：Claude 正在等你补充输入
- `Elicitation`：等待你填写表单、登录或提供结构化信息
- `StopFailure`：Claude 真正无法继续
- `TaskCompleted`：任务完成（主要用于 task/team 工作流）
- `SessionEnd`：会话结束

这套映射的目标是：**优先保证“需要你回来处理”的通知准时到达，同时降低过程态误报。**

## OpenCode 默认事件

OpenCode 现在不再复用 Claude 风格的 `hooks` JSON，而是改成官方插件机制。默认插件会监听：

- `permission.asked`：需要你授权继续
- `session.error`：会话真正出错
- `session.idle`：当前轮次进入空闲

这样可以避免继续依赖不稳定的私有事件格式。

## Codex 默认事件

Codex 官方 hooks 目前还是实验能力，且事件面比 Claude Code 更窄，没有直接的 `permission_prompt` / `idle_prompt` 事件。当前默认接法是：

- `PostToolUse(Bash)`：只在明显需要人工处理的 Bash 错误时提醒
- `Stop`：如果 `last_assistant_message` 看起来是在等你回复，则按高优先级提醒；否则当作低优先级“本轮结束”

这意味着 Codex 的“需要你介入”提醒是**能力边界内的 best-effort**，没有 Claude Code 那么精确。

## 扩展到其他工具

通知脚本现在支持统一的 CLI 入口，未来接入其他工具时只要把对应事件映射成统一参数即可：

```bash
~/.cc-notify/bin/smart-notify.sh \
  --source my-tool \
  --event approval_required \
  --kind intervention \
  --title "⚠️ 需要确认" \
  --body "my-tool 正在等待你的确认" \
  --priority high
```

## GitHub 使用建议

这个仓库现在只使用通用路径约定，例如 `~/.claude`、`~/.cursor`、`~/.codex`、`~/.config/opencode` 和 `~/.cc-notify`，没有任何写死的个人绝对路径。对外发布时，README 和安装脚本可以直接复用；用户只需要：

1. clone 仓库
2. 运行 `./install.sh`
3. 选择自己安装过的工具
4. 按提示完成 Bark 配置和系统授权

## 故障排查

### 没有收到通知

1. 确认 Bark Key 正确
2. 手动测 Bark：`curl "https://api.day.app/YOUR_KEY/测试/内容"`
3. 确认辅助功能已授权

### 一直在发通知

- 确认已授权辅助功能（否则无法判断前台应用）
- 查看当前前台应用：`osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'`

### 从来不发通知

- 检查 `~/.cc-notify/config.json` 里的 Bark Key
- 检查网络

### 调试模式

```bash
# 开启详细日志
CC_NOTIFY_DEBUG=1 ~/.cc-notify/bin/smart-notify.sh "测试" "内容" "normal"
```

输出示例：
```
[DEBUG] 配置加载成功: BARK_URL=https://api.day.app
[DEBUG] 锁屏状态: 0
[DEBUG] 应用信息: [Cursor    /Applications/Cursor.app    com.todesktop.230313mzl4w4u92]
[DEBUG] 进程名: [Cursor]
[DEBUG] 应用路径: [/Applications/Cursor.app]
[DEBUG] Bundle ID: [com.todesktop.230313mzl4w4u92]
[DEBUG] 匹配编辑器应用（路径）: /Applications/Cursor.app
[DEBUG] 用户在关注中，不发送通知
```

## 参考

- [Bark](https://github.com/Finb/Bark) - iOS 通知推送
- [Claude Code Hooks](https://docs.anthropic.com/claude-code/hooks) - 官方文档
- [Cursor Hooks (beta)](https://cursor.com/changelog/1-7/) - 官方发布说明
- [Cursor](https://cursor.com) - AI Code Editor
- [OpenAI Codex Hooks](https://developers.openai.com/codex/hooks) - 官方文档
- [OpenCode Plugins](https://opencode.ai/docs/plugins/) - 官方文档
- [OpenCode](https://opencode.ai) - 开源 AI 编程助手

## Changelog

详见 [CHANGELOG.md](CHANGELOG.md)

## License

MIT
