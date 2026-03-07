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

# 检测 Obsidian（Claudian 插件宿主）
detect_obsidian() {
    # 检查 macOS 应用
    if [ -d "/Applications/Obsidian.app" ]; then
        echo "installed"
    # 检查 Linux
    elif command -v obsidian &>/dev/null; then
        echo "installed"
    else
        echo "not_installed"
    fi
}

# 检测 Claudian 插件（需要指定 vault 路径）
detect_claudian() {
    local vault_path="$1"

    # 如果没有指定 vault 路径，尝试从常见位置查找
    if [ -z "$vault_path" ]; then
        # 尝试查找用户的 Obsidian vault
        local possible_paths=(
            "$HOME/Documents/Obsidian"
            "$HOME/obsidian"
            "$HOME/Obsidian"
            "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents"
        )

        for path in "${possible_paths[@]}"; do
            if [ -d "$path" ]; then
                # 查找 .obsidian/plugins/claudian 目录
                if find "$path" -type d -name "claudian" -path "*/.obsidian/plugins/*" 2>/dev/null | head -1 | grep -q .; then
                    echo "installed"
                    return
                fi
            fi
        done
        echo "not_installed"
        return
    fi

    # 检查指定 vault 中的 Claudian 插件
    if [ -d "$vault_path/.obsidian/plugins/claudian" ]; then
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
    local obsidian=$(detect_obsidian)
    local claudian=$(detect_claudian)

    jq -n \
        --arg claude "$claude" \
        --arg cursor "$cursor" \
        --arg opencode "$opencode" \
        --arg obsidian "$obsidian" \
        --arg claudian "$claudian" \
        '{
            "claude-code": $claude,
            "cursor": $cursor,
            "opencode": $opencode,
            "obsidian": $obsidian,
            "claudian": $claudian
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
    local obsidian=$(echo "$result" | jq -r '.obsidian')
    local claudian=$(echo "$result" | jq -r '.claudian')

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

    if [ "$obsidian" = "installed" ]; then
        echo "  ✅ Obsidian (Claudian)"
    else
        echo "  ⚠️  Obsidian (未安装)"
    fi

    if [ "$claudian" = "installed" ]; then
        echo "  ✅ Claudian 插件已安装"
    else
        echo "  ℹ️  Claudian 插件 (未检测到)"
    fi
}

# 如果直接运行此脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    detect_all
fi
