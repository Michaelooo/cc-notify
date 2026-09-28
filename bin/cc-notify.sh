#!/usr/bin/env bash
# npm 全局安装入口：转发到仓库自带的交互式安装器
# 安装器会把 lib/templates 复制到 ~/.cc-notify 并写入各 AI 工具的 hooks
set -e
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$PKG_DIR/install.sh" "$@"
