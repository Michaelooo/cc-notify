# cc-notify

> **AI 写代码时，一旦需要你介入，立刻通知你** —— 不错过权限确认、选择确认和报错，快速响应、少干等。

[![macOS](https://img.shields.io/badge/platform-macos-lightgrey)](https://www.apple.com/macos)
[![Bark](https://img.shields.io/badge/push-Bark-green)](https://github.com/Finb/Bark)

## 为什么需要它

在 AI Coding 里，模型经常需要你**当场介入**：

- 要执行命令 / 改文件，等你点「允许」
- 问你「用 A 还是 B」，等你选
- 任务出错或完成，等你下一步

如果你这时在查文档、开会或锁屏，**你根本不知道**，AI 在那边空等，你也白白浪费时间。  
**cc-notify** 会在这些「需要人介入」的时刻，把通知推到你的手机，让你马上回来处理，而不是事后才发现卡住了。

## 核心理念

```
需要你确认/选择/处理 → 尽快通知（高优先级，短延迟即发）
任务完成但你人不在 → 通知你（锁屏/切走才发，避免刷屏）
你正盯着终端看     → 不打扰（你已经看到了）
```

## 支持的工具

| 工具 | 状态 | 会通知的「需介入」时刻 |
|-----|------|------------------------|
| Claude Code | ✅ | 权限确认、等待输入、任务完成、停止 |
| Cursor | ✅ | 停止、Shell 执行后 |
| OpenCode | ✅ | 复用 Claude Code 事件格式 |

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

## 典型场景

### 需要你确认时 → 马上通知

```
1. Claude: "要执行 npm install 吗？" / "用 React 还是 Vue？"
2. 你在浏览器查资料，没看终端
3. 几秒内 → 手机收到「需要确认」通知
4. 你点开，做出选择，AI 继续跑
```

### 任务完成但你人不在 → 通知你回来

```
1. 终端: claude "帮我修这个 bug"
2. 你锁屏去开会
3. 任务完成
4. 手机收到通知 → 你知道可以回来看了
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
| **高** | 权限确认、等待输入、执行失败 | 短延迟（约 5 秒）后发送，便于你快速介入 |
| **中** | 任务全部完成 | 仅在你锁屏或切走时发送 |
| **低** | 单轮对话结束 | 仅锁屏时发送 |

## 目录结构

```
cc-notify/
├── install.sh              # 一键安装入口
├── lib/
│   ├── common.sh           # 公共函数
│   ├── detect.sh           # 工具检测
│   ├── configure.sh        # 配置写入
│   └── notify.sh           # 核心通知脚本
├── templates/
│   ├── claude-hooks.json   # Claude Code hooks
│   ├── cursor-hooks.json   # Cursor hooks
│   └── opencode-hooks.json # OpenCode hooks
├── doc/
│   └── AI-Coding-智能通知系统-最终版.md
└── README.md
```

## 配置文件

| 文件 | 路径 |
|-----|------|
| 用户配置 | `~/.cc-notify/config.json` |
| 通知脚本 | `~/.cc-notify/bin/smart-notify.sh` |
| Claude Code | `~/.claude/settings.json` |
| Cursor | `~/.cursor/hooks.json` |
| OpenCode | `~/.config/opencode/opencode.json` |

## 测试

```bash
# 普通通知
~/.cc-notify/bin/smart-notify.sh "测试" "安装成功" "normal"

# 高优先级（短延迟后发，模拟「需要介入」）
~/.cc-notify/bin/smart-notify.sh "测试" "需要确认" "high"

# 低优先级
~/.cc-notify/bin/smart-notify.sh "测试" "低优先级" "low"
```

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

## 参考

- [Bark](https://github.com/Finb/Bark) - iOS 通知推送
- [Claude Code Hooks](https://docs.anthropic.com/claude-code/hooks) - 官方文档
- [Cursor](https://cursor.com) - AI Code Editor
- [OpenCode](https://opencode.ai) - 开源 AI 编程助手

## License

MIT
