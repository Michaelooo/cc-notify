#!/bin/bash
# cc-notify 工具检测模块

# 检测 Claude Code
detect_claude_code() {
    if command -v claude &>/dev/null; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

# 检测 Cursor
detect_cursor() {
    # 检查 macOS 应用
    if [ -d "/Applications/Cursor.app" ]; then
        echo "installed"
    # 检查 Linux
    elif command -v cursor &>/dev/null; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

# 检测 OpenCode
detect_opencode() {
    if command -v opencode &>/dev/null; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

# 检测所有工具（返回 JSON）
detect_all() {
    local claude=$(detect_claude_code)
    local cursor=$(detect_cursor)
    local opencode=$(detect_opencode)

    jq -n \
        --arg claude "$claude" \
        --arg cursor "$cursor" \
        --arg opencode "$opencode" \
        '{
            "claude-code": $claude,
            "cursor": $cursor,
            "opencode": $opencode
        }'
}

# 打印检测结果
print_detection_result() {
    local result="$1"

    echo ""
    echo "检测结果:"

    local claude=$(echo "$result" | jq -r '.["claude-code"]')
    local cursor=$(echo "$result" | jq -r '.cursor')
    local opencode=$(echo "$result" | jq -r '.opencode')

    if [ "$claude" = "installed" ]; then
        echo "  ✅ Claude Code"
    else
        echo "  ⚠️  Claude Code (未安装)"
    fi

    if [ "$cursor" = "installed" ]; then
        echo "  ✅ Cursor"
    else
        echo "  ⚠️  Cursor (未安装)"
    fi

    if [ "$opencode" = "installed" ]; then
        echo "  ✅ OpenCode"
    else
        echo "  ⚠️  OpenCode (未安装)"
    fi
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    detect_all
fi
