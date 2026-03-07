#!/bin/bash
# cc-notify 配置管理模块

# 获取模板目录
get_templates_dir() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$script_dir")/templates"
}

# 写入用户配置文件（合并模式）
write_user_config() {
    local bark_key="$1"
    local device_name="$2"
    local target="$HOME/.cc-notify/config.json"

    ensure_dir "$(dirname "$target")"

    # 如果没有提供设备名称，使用主机名
    if [ -z "$device_name" ]; then
        device_name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "Mac")
    fi

    if [ -f "$target" ]; then
        # 保留现有配置，只更新 bark key 和设备名称
        local tmp_file="${target}.tmp"
        jq --arg key "$bark_key" --arg device "$device_name" \
            '.bark.key = $key | .device.name = $device' "$target" > "$tmp_file"
        mv "$tmp_file" "$target"
        log_success "用户配置: $target (已更新 Bark Key 和设备名称)"
    else
        jq -n \
            --arg version "1.0.0" \
            --arg key "$bark_key" \
            --arg device "$device_name" \
            '{
                "version": $version,
                "bark": {
                    "key": $key,
                    "url": "https://api.day.app"
                },
                "device": {
                    "name": $device,
                    "terminal": ""
                },
                "tools": {
                    "claude-code": { "enabled": false },
                    "cursor": { "enabled": false },
                    "opencode": { "enabled": false },
                    "claudian": { "enabled": false }
                },
                "smart_detect": {
                    "enabled": true,
                    "terminal_apps": ["iTerm", "Terminal", "Kitty", "Warp", "Alacritty"],
                    "editor_apps": ["Cursor", "Code", "JetBrains", "IntelliJ"]
                },
                "dedup": {
                    "enabled": true,
                    "window_seconds": 60,
                    "threshold": 3
                }
            }' > "$target"
        log_success "用户配置: $target (已创建)"
    fi
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

# 通用的 hooks 合并函数
# 合并策略：保留用户现有配置，添加模板中的新 hooks
merge_hooks_config() {
    local target="$1"
    local template="$2"
    local tool_name="$3"

    # 备份现有配置
    backup_file "$target"

    # 确保目录存在
    ensure_dir "$(dirname "$target")"

    if [ ! -f "$target" ]; then
        # 目标不存在，直接复制模板
        cp "$template" "$target"
        log_success "$tool_name: $target (已创建)"
        return 0
    fi

    # 检查文件格式
    if ! jq empty "$target" 2>/dev/null; then
        log_error "目标配置文件格式错误: $target"
        return 1
    fi

    if ! jq empty "$template" 2>/dev/null; then
        log_error "模板配置文件格式错误: $template"
        return 1
    fi

    # 执行合并
    local tmp_file="${target}.tmp"

    # 简化合并策略：
    # 1. 保留用户现有的所有配置
    # 2. 只在 hooks 对象内添加新的事件类型
    # 3. 如果用户已有同类型 hooks，不覆盖
    jq --slurpfile tmpl "$template" '
        # 用户现有 hooks
        (.hooks // {}) as $user_hooks |
        # 模板 hooks
        ($tmpl[0].hooks // {}) as $tmpl_hooks |

        # 用户已有的 hook 类型
        ($user_hooks | keys) as $user_keys |

        # 需要添加的 hook 类型（模板有但用户没有的）
        ($tmpl_hooks | to_entries | map(select(.key | IN($user_keys[]) | not)) | from_entries) as $new_hooks |

        # 合并后的 hooks（用户现有 + 新添加）
        ($user_hooks * $new_hooks) as $merged_hooks |

        # 最终结果：保留用户的其他配置，添加合并后的 hooks
        . + {hooks: $merged_hooks} + ($tmpl[0] | del(.hooks))
    ' "$target" > "$tmp_file"

    if [ $? -eq 0 ] && [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$target"
        log_success "$tool_name: $target (已合并，保留现有配置)"
    else
        rm -f "$tmp_file"
        log_warning "$tool_name: 合并失败，保留原配置"
        return 1
    fi

    return 0
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

    merge_hooks_config "$target" "$template" "Claude Code"
    local result=$?

    if [ $result -eq 0 ]; then
        update_tool_status "claude-code" "true"
    fi

    return $result
}

# 写入 Cursor hooks（合并模式）
write_cursor_hooks() {
    local templates_dir=$(get_templates_dir)
    local template="$templates_dir/cursor-hooks.json"
    local target="$HOME/.cursor/hooks.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    merge_hooks_config "$target" "$template" "Cursor"
    local result=$?

    if [ $result -eq 0 ]; then
        update_tool_status "cursor" "true"
    fi

    return $result
}

# 写入 OpenCode hooks（合并模式）
write_opencode_hooks() {
    local templates_dir=$(get_templates_dir)
    local template="$templates_dir/opencode-hooks.json"
    local target="$HOME/.config/opencode/opencode.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    merge_hooks_config "$target" "$template" "OpenCode"
    local result=$?

    if [ $result -eq 0 ]; then
        update_tool_status "opencode" "true"
    fi

    return $result
}

# 配置 Claudian（使用 Claude Code 的 hooks）
# Claudian 是基于 Claude Code SDK 的 Obsidian 插件
# 它会自动继承 ~/.claude/settings.json 中配置的 hooks
configure_claudian() {
    log_info "Claudian 使用 Claude Code 的 hooks 配置"
    log_info "将自动配置 Claude Code hooks..."

    # 配置 Claude Code hooks（Claudian 会继承）
    merge_claude_hooks
    local result=$?

    if [ $result -eq 0 ]; then
        update_tool_status "claudian" "true"
        log_success "Claudian 配置完成（继承 Claude Code hooks）"
    fi

    return $result
}

# 安装通知脚本到用户目录
install_notify_script() {
    local templates_dir=$(get_templates_dir)
    local lib_dir="$(dirname "$templates_dir")/lib"
    local target_dir="$HOME/.cc-notify/bin"

    ensure_dir "$target_dir"

    cp "$lib_dir/notify.sh" "$target_dir/smart-notify.sh"
    chmod +x "$target_dir/smart-notify.sh"

    log_success "通知脚本: $target_dir/smart-notify.sh"
}
