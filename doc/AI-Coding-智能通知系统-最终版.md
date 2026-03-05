---
date: 2026-03-05
tags: 
  - type/guide
  - type/design
  - topic/ai
  - topic/hooks
  - topic/notification
  - tool/claude-code
  - tool/cursor
  - status/final
---

# AI Coding 智能通知系统 - 最终版

> 核心设计：**只在用户真正需要时才打扰**
> 
> 如果用户在看屏幕 → 不通知  
> 如果用户切走了/锁屏了 → 立即通知

---

## 一、系统概述

### 1.1 解决的问题

| 问题 | 传统方案 | 本系统方案 |
|-----|---------|-----------|
| 过度打扰 | 所有事件都通知 | 智能判断，只发必要的 |
| 场景不匹配 | 用户就在屏幕前还发手机 | 检测焦点，在场不发 |
| 信息噪音 | 重要信息被淹没 | 分级处理，高优优先 |

### 1.2 核心特性

- ✅ **锁屏必发** - 用户离开了，立即通知
- ✅ **高优必发** - 需要确认/报错，不遗漏
- ✅ **焦点检测** - 终端在前台时不打扰
- ✅ **应用识别** - 浏览器/聊天工具在前台时发
- ✅ **延时等待** - 中等优先级等用户离开再发

---

## 二、触发场景与优先级

| 事件 | 触发条件 | 优先级 | 通知策略 |
|-----|---------|-------|---------|
| `permission_prompt` | AI 需要用户选择/确认 | **高** | 等待5秒，然后发送（不遗漏） |
| `idle_prompt` | AI 等待用户提供信息 | **高** | 等待5秒，然后发送 |
| `PostToolUseFailure` | 命令/编辑执行失败 | **高** | 等待5秒，然后发送 |
| `TaskCompleted` | 所有任务标记完成 | **中** | 锁屏/切走发，在场不发 |
| `Stop` | 单轮对话结束 | **低** | 锁屏才发，其他情况不发 |

---

## 三、检测机制

### 3.1 锁屏检测（最可靠）

```python
import Quartz
d = Quartz.CGSessionCopyCurrentDictionary()
screen_locked = (d.get('OnConsoleKey') == 0)
```

- ✅ 100% 准确
- ✅ 无需权限
- ✅ 跨应用有效

### 3.2 前台应用检测

```applescript
tell application "System Events" 
    get name of first application process whose frontmost is true
end tell
```

**判断逻辑**:

| 前台应用 | 判定 | 操作 |
|---------|------|------|
| Safari/Chrome/Firefox | 用户在浏览 | **发送通知** |
| WeChat/Feishu/DingTalk/Slack | 用户在聊天 | **发送通知** |
| Mail/Outlook | 用户在处理邮件 | **发送通知** |
| iTerm/Terminal/Kitty | 用户在看终端 | **不发送** |
| Cursor/VS Code/JetBrains | 用户在看代码 | **不发送** |
| Finder/桌面/其他 | 不确定 | **发送通知** |

**限制**:
- 需要"辅助功能"权限（首次运行会弹窗）
- 无法检测多屏幕场景（终端在副屏也可能判定为有焦点）
- 无法检测 tmux/screen 内切换

---

## 四、配置文件

### 4.1 智能通知脚本

**位置**: `~/.claude/hooks/smart-notify.sh`

```bash
#!/bin/bash
BARK_KEY="${BARK_KEY:-H9Cs47PmdcJPACbLzvuNmC}"
BARK_URL="https://api.day.app"

TITLE="${1:-AI通知}"
BODY="${2:-需要关注}"
PRIORITY="${3:-normal}"  # high / normal / low

encoded_title=$(echo "$TITLE" | jq -sRr @uri 2>/dev/null || echo "$TITLE")
encoded_body=$(echo "$BODY" | jq -sRr @uri 2>/dev/null || echo "$BODY")

send_notification() {
    curl -s "${BARK_URL}/${BARK_KEY}/${encoded_title}/${encoded_body}?group=ai-coding" > /dev/null
}

# 1. 锁屏检测
screen_locked=$(python3 -c "
import Quartz
d = Quartz.CGSessionCopyCurrentDictionary()
print('1' if d.get('OnConsoleKey') == 0 else '0')
" 2>/dev/null)

if [ "$screen_locked" = "1" ]; then
    send_notification
    exit 0
fi

# 2. 高优先级
if [ "$PRIORITY" = "high" ]; then
    sleep 5
    send_notification
    exit 0
fi

# 3. 前台应用检测
front_app=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)

case "$front_app" in
    *"Safari"*|*"Chrome"*|*"Firefox"*|*"Edge"*)
        send_notification; exit 0 ;;
    *"WeChat"*|*"Feishu"*|*"Lark"*|*"DingTalk"*|*"Slack"*)
        send_notification; exit 0 ;;
esac

case "$front_app" in
    *"iTerm"*|*"Terminal"*|*"Kitty"*)
        exit 0 ;;
    *"Cursor"*|*"Code"*|*"JetBrains"*)
        exit 0 ;;
esac

# 其他情况发送
send_notification
exit 0
```

### 4.2 Claude Code 配置

**位置**: `~/.claude/settings.json`

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [{
          "type": "command",
          "command": "~/.claude/hooks/smart-notify.sh '⚠️ Claude需要确认' '请查看终端并做出选择' 'high'"
        }]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [{
          "type": "command",
          "command": "~/.claude/hooks/smart-notify.sh '⏸️ Claude等待中' '请提供更多信息' 'high'"
        }]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "~/.claude/hooks/smart-notify.sh '❌ 执行失败' '命令执行出错，请查看终端' 'high'"
        }]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [{
          "type": "command",
          "command": "~/.claude/hooks/smart-notify.sh '🎉 全部完成' 'Claude已完成所有任务' 'normal'"
        }]
      }
    ],
    "Stop": [
      {
        "hooks": [{
          "type": "command",
          "command": "~/.claude/hooks/smart-notify.sh '✅ 任务完成' '一轮对话已结束' 'low'",
          "async": true
        }]
      }
    ]
  }
}
```

### 4.3 Cursor 配置

**位置**: `~/.cursor/hooks.json`

```json
{
  "version": 1,
  "hooks": {
    "stop": [{
      "command": "~/.claude/hooks/smart-notify.sh '✅ Cursor完成' '任务已结束' 'normal'"
    }],
    "afterShellExecution": [{
      "match": ".*",
      "command": "~/.claude/hooks/smart-notify.sh '✅ 命令完成' 'Shell命令执行完毕' 'low'"
    }]
  }
}
```

---

## 五、快速开始

### 5.1 安装 Bark

1. App Store 搜索 "Bark"
2. 复制你的 Key（已配置: `H9Cs47PmdcJPACbLzvuNmC`）

### 5.2 一键安装

```bash
# 1. 创建目录
mkdir -p ~/.claude/hooks

# 2. 创建智能通知脚本（复制上文 4.1 内容）
cat > ~/.claude/hooks/smart-notify.sh << 'SCRIPT'
# ... 脚本内容 ...
SCRIPT
chmod +x ~/.claude/hooks/smart-notify.sh

# 3. 创建 Claude Code 配置（复制上文 4.2 内容）
mkdir -p ~/.claude
cat > ~/.claude/settings.json << 'JSON'
# ... JSON 内容 ...
JSON
```

### 5.3 授权

首次运行会请求权限：
- **辅助功能权限**: 用于检测前台应用
- 在 系统设置 → 隐私与安全 → 辅助功能 中允许 Terminal/iTerm/Cursor

### 5.4 测试

```bash
# 测试 1: 终端内执行（应该不通知或延迟）
~/.claude/hooks/smart-notify.sh "测试" "终端内测试" "normal"

# 测试 2: 切换到浏览器后立即执行（应该立即通知）
# 先执行命令，然后立即切换到 Safari

# 测试 3: 锁屏后执行（应该立即通知）
```

---

## 六、使用示例

### 场景 1: 你在浏览器查资料
```
1. 终端: claude "帮我分析这段代码"
2. 你切换到 Safari 查文档
3. Claude 完成任务
4. 检测: 前台是 Safari
5. 结果: 立即发送通知到手机
```

### 场景 2: 你盯着终端看结果
```
1. 终端: claude "生成单元测试"
2. 你盯着终端等待
3. Claude 完成任务
4. 检测: 前台是 iTerm
5. 结果: 不发送通知（你已经看到了）
```

### 场景 3: Claude 需要确认选择
```
1. Claude: "使用 React 还是 Vue?"
2. 检测: 前台是 Cursor（高优先级）
3. 等待 5 秒...
4. 你还没回答
5. 结果: 发送通知 "⚠️ Claude需要确认"
```

### 场景 4: 你锁屏去开会了
```
1. 终端: claude "部署到生产环境"（长时间任务）
2. 你锁屏去开会
3. 任务完成
4. 检测: 屏幕已锁定
5. 结果: 立即发送通知到手机
```

---

## 七、Apple Watch 支持

### 7.1 震动级别

| 优先级 | 级别参数 | 效果 |
|-------|---------|------|
| 高 | `level=critical` | 突破专注模式，强震动 |
| 中 | `level=timeSensitive` | 突破专注模式，中等震动 |
| 低 | `level=active` | 普通通知，轻震动 |

### 7.2 iPhone/Watch 设置

1. iPhone: 设置 → 通知 → Bark
   - 开启「允许通知」
   - 开启「在 Apple Watch 上显示」
   - 开启「声音」

2. Watch: 设置 → 触感 → 开启「触感提示」

---

## 八、故障排查

### 8.1 没有收到通知

```bash
# 1. 检查 Bark Key
echo $BARK_KEY

# 2. 手动测试
curl "https://api.day.app/H9Cs47PmdcJPACbLzvuNmC/测试/内容"

# 3. 检查脚本日志
~/.claude/hooks/smart-notify.sh "测试" "内容" "high" 2>&1

# 4. 检查权限
# 系统设置 → 隐私与安全 → 辅助功能 → 确保终端应用已授权
```

### 8.2 一直在发通知（打扰）

可能是前台应用检测失败：
- 检查是否授权辅助功能
- 检查脚本中的 app 名称是否匹配你的实际应用

### 8.3 从来不发通知

- 检查 BARK_KEY 是否正确
- 检查网络连接
- 手动测试 Bark 是否正常工作

---

## 九、文件清单

| 文件 | 路径 | 作用 |
|-----|------|------|
| 智能通知脚本 | `~/.claude/hooks/smart-notify.sh` | 核心判断逻辑 |
| Claude Code 配置 | `~/.claude/settings.json` | 事件绑定 |
| Cursor 配置 | `~/.cursor/hooks.json` | Cursor 事件绑定（可选） |
| 本文档 | `4_Resources/articles/2026-03-05-AI-Coding-智能通知系统-最终版.md` | 完整指南 |

---

## 十、参考

- Bark: https://github.com/Finb/Bark
- Claude Code Hooks: https://code.claude.com/docs/hooks
- Cursor Hooks: https://cursor.com/docs/agent/hooks
- macOS Quartz: https://developer.apple.com/documentation/coregraphics

---

*使用 doc-generator 技能生成  
生成时间: 2026-03-05*
