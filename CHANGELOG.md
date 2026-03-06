# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
