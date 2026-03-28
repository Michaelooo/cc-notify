# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Claude Code / OpenCode 默认 hooks 改为基于精确事件分类，不再把 `Stop` 当成任务完成
- 默认移除 `PostToolUseFailure` 的泛化错误提醒，减少过程态误报
- Cursor 默认不再监听 `afterShellExecution`，降低 Shell 过程噪音
- OpenCode 改为官方插件机制，不再假设兼容 Claude Code hooks
- 通知脚本支持读取 hook stdin JSON，按事件自动决定标题、正文和优先级
- 安装合并逻辑会升级已有 cc-notify hooks，而不是一直保留旧模板

### Added
- 统一 CLI 参数接口，便于接入其他 AI Coding 工具
- `CC_NOTIFY_DRY_RUN` / `CC_NOTIFY_FORCE_NOTIFY` 调试能力，方便本地验证事件分类
- Codex 全局 hooks 集成与 `codex_hooks` feature 自动启用

## [1.0.0] - 2026-03-06

### Added
- 初始版本发布
- 支持 Claude Code、Cursor、OpenCode 三种 AI Coding 工具
- 智能通知核心功能
  - 锁屏检测（macOS Quartz）
  - 前台应用检测（三重匹配：路径 > Bundle ID > 进程名）
  - 高/中/低三级优先级通知策略
- 一键安装脚本（curl 安装）
- 配置合并策略（保留用户现有配置）
- 调试模式（`CC_NOTIFY_DEBUG=1`）

### Features
- **智能判断**：用户在终端/编辑器时不打扰
- **锁屏必发**：用户离开时立即通知
- **高优必发**：权限确认/报错不遗漏
- **延时重检**：高优先级通知5秒后重新检查用户状态

### Technical
- 使用 `jq` 进行 JSON 配置合并
- 使用 `osascript` 获取前台应用信息
- 使用 Python Quartz 检测锁屏状态
- 支持 Electron 应用的特殊处理

[1.0.0]: https://github.com/USER/cc-notify/releases/tag/v1.0.0
