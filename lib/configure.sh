#!/bin/bash
# cc-notify 配置管理模块

# 获取模板目录
get_templates_dir() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$script_dir")/templates"
}

# 写入用户配置文件
write_user_config() {
    local bark_key="$1"
    local target="$HOME/.cc-notify/config.json"

    ensure_dir "$(dirname "$target")"

    jq -n \
        --arg version "1.0.0" \
        --arg key "$bark_key" \
        '{
            "version": $version,
            "bark": {
                "key": $key,
                "url": "https://api.day.app"
            },
            "tools": {
                "claude-code": { "enabled": false },
                "cursor": { "enabled": false },
                "opencode": { "enabled": false }
            },
            "smart_detect": {
                "enabled": true,
                "terminal_apps": ["iTerm", "Terminal", "Kitty", "Warp", "Alacritty"],
                "editor_apps": ["Cursor", "Code", "JetBrains", "IntelliJ"]
            }
        }' > "$target"

    log_success "配置文件: $target"
}

# 更新工具启用状态
update_tool_status() {
    local tool="$1"
    local enabled="$2"
    local target="$HOME/.cc-notify/config.json"

    if [ -f "$target" ]; then
        local enabled_json="true"
        [ "$enabled" = "false" ] && enabled_json="false"

        jq --arg tool "$tool" --argjson enabled "$enabled_json" \
            '.tools[$tool].enabled = $enabled' "$target" > "${target}.tmp"
        mv "${target}.tmp" "$target"
    fi
}

# 合并 Claude Code hooks
merge_claude_hooks() {
    local templates_dir=$(get_templates_dir)
    local template="$templates_dir/claude-hooks.json"
    local target="$HOME/.claude/settings.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    # 备份现有配置
    backup_file "$target"

    # 确保目录存在
    ensure_dir "$(dirname "$target")"

    # 合并或创建配置
    if [ -f "$target" ]; then
        # 读取现有配置中的非 hooks 部分，然后合并
        jq -s '.[0] * .[1]' "$target" "$template" > "${target}.tmp"
        mv "${target}.tmp" "$target"
        log_success "Claude Code: $target (已合并)"
    else
        cp "$template" "$target"
        log_success "Claude Code: $target (已创建)"
    fi

    # 更新 cc-notify 配置
    update_tool_status "claude-code" "true"
}

# 写入 Cursor hooks
write_cursor_hooks() {
    local templates_dir=$(get_templates_dir)
    local template="$templates_dir/cursor-hooks.json"
    local target="$HOME/.cursor/hooks.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    # 备份现有配置
    backup_file "$target"

    # 确保目录存在
    ensure_dir "$(dirname "$target")"

    # 写入配置
    cp "$template" "$target"
    log_success "Cursor: $target"

    # 更新 cc-notify 配置
    update_tool_status "cursor" "true"
}

# 写入 OpenCode hooks（使用 Claude Code 兼容格式）
write_opencode_hooks() {
    local templates_dir=$(get_templates_dir)
    local template="$templates_dir/opencode-hooks.json"
    local target="$HOME/.config/opencode/opencode.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    # 备份现有配置
    backup_file "$target"

    # 确保目录存在
    ensure_dir "$(dirname "$target")"

    # 合并或创建配置
    if [ -f "$target" ]; then
        jq -s '.[0] * .[1]' "$target" "$template" > "${target}.tmp"
        mv "${target}.tmp" "$target"
        log_success "OpenCode: $target (已合并)"
    else
        cp "$template" "$target"
        log_success "OpenCode: $target (已创建)"
    fi

    # 更新 cc-notify 配置
    update_tool_status "opencode" "true"
}

# 安装通知脚本到用户目录
install_notify_script() {
    local templates_dir=$(get_templates_dir)
    local lib_dir="$(dirname "$templates_dir")/lib"
    local target_dir="$HOME/.cc-notify/bin"

    ensure_dir "$target_dir"

    # 复制通知脚本
    cp "$lib_dir/notify.sh" "$target_dir/smart-notify.sh"
    chmod +x "$target_dir/smart-notify.sh"

    log_success "通知脚本: $target_dir/smart-notify.sh"
}
