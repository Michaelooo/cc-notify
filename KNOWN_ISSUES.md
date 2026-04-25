# Known Issues

## 1. Stop Hook 触发时机问题

**状态**: 已确认并采用去重方案缓解 (Claude Code 官方行为)

**描述**:
`Stop` hook 会在每次 Claude 响应后触发，而不仅仅是任务完成时。这会导致在多轮对话中连续触发多次 Stop。

**影响版本**: 所有版本

**官方 Issue**: [anthropics/claude-code#15250](https://github.com/anthropics/claude-code/issues/15250)

**当前处理方式**:
- 重新订阅 `Stop`（`low` 优先级），以确保单 agent 普通对话完成也能收到通知
- Stop 事件使用独立的去重窗口（默认 150 秒，可通过 `CC_NOTIFY_STOP_DEDUP_WINDOW` 调整），同一会话（session_id + cwd）在窗口内只发一条
- Stop 指纹由 `session_id|cwd|source` 组成，而非消息内容，确保同会话连续触发时合并为一条
- `SessionEnd` 作为补充兜底（用户显式退出时仍会触发）
- `TaskCompleted` 用于 multi-agent 工作流中的任务完成

**相关配置**:
```json
{
  “hooks”: {
    “Stop”: [...],           // 每轮响应结束，150s 去重窗口聚合
    “TaskCompleted”: [...],  // 任务完成时触发（multi-agent）
    “SessionEnd”: [...]      // 会话结束时触发
  }
}
```

---

## 2. TaskCompleted Hook 文档缺失

**状态**: 已确认 (官方文档遗漏)

**描述**:
`TaskCompleted` 是 Claude Code v2.1.33 添加的有效 hook 事件，但官方文档中缺少相关说明。

**官方 Issue**: [anthropics/claude-code#23545](https://github.com/anthropics/claude-code/issues/23545)

**说明**:
- `TaskCompleted` 在 shared task list 中的任务完成时触发
- 主要用于 multi-agent workflows
- 如果不使用 agent teams，此 hook 可能不会触发

---

## 3. Bark "Decryption Failed" 错误

**状态**: 已修复

**描述**:
旧版本使用 `ciphertext` 字段用于去重，但 Bark 将其识别为 AES 加密参数并尝试解密，导致显示 "Decryption Failed"。

**解决方案**:
已在 v1.0.0 后的版本中移除 `ciphertext` 字段。

**相关提交**: 17854ef

---

## 4. Codex Hooks 仍属实验能力

**状态**: 官方限制

**描述**:
Codex 官方 hooks 当前仍是 experimental，事件面也比 Claude Code 更窄。它没有直接暴露 `permission_prompt` / `idle_prompt` 这类显式“正在等你”的事件，因此 cc-notify 只能基于 `Stop.last_assistant_message` 和 `PostToolUse(Bash)` 做 best-effort 判断。

**影响**:
- Codex 的“需要你介入”提醒准确率低于 Claude Code
- 某些等待用户确认的场景无法像 Claude Code 那样被精确捕获

**当前处理方式**:
- 对 `Stop` 做“是否在等你回复”的启发式判断
- 只对明显需要人工处理的 Bash 错误发高优通知
- 在 README 中明确说明这是能力边界，不把 Codex 支持描述成和 Claude 等价

---

## 参考资料

- [Claude Code Hooks 官方文档](https://code.claude.com/docs/en/hooks)
- [Claude Code GitHub Issues](https://github.com/anthropics/claude-code/issues)
