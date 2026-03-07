# Known Issues

## 1. Stop Hook 触发时机问题

**状态**: 已确认 (Claude Code 官方行为)

**描述**:
`Stop` hook 会在每次 Claude 响应后触发，而不仅仅是任务完成时。这会导致在多轮对话中收到多次"对话结束"通知。

**影响版本**: 所有版本

**官方 Issue**: [anthropics/claude-code#15250](https://github.com/anthropics/claude-code/issues/15250)

**解决方案**:
- 使用 `SessionEnd` hook 替代 `Stop` hook 来接收会话结束通知
- 使用 `TaskCompleted` hook 来接收任务完成通知（注意：仅适用于 multi-agent workflows 和 shared task list）

**相关配置**:
```json
{
  "hooks": {
    "TaskCompleted": [...],  // 任务完成时触发
    "SessionEnd": [...]      // 会话结束时触发
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

## 参考资料

- [Claude Code Hooks 官方文档](https://code.claude.com/docs/en/hooks)
- [Claude Code GitHub Issues](https://github.com/anthropics/claude-code/issues)
