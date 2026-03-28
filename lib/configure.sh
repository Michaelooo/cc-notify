#!/bin/bash
# cc-notify 配置管理模块

CONFIGURE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGURE_ROOT_DIR="$(cd "$CONFIGURE_LIB_DIR/.." && pwd)"

get_templates_dir() {
    echo "$CONFIGURE_ROOT_DIR/templates"
}

get_lib_dir() {
    echo "$CONFIGURE_ROOT_DIR/lib"
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

    # 清理可能被旧版 read_input 捕获进去的提示词和 ANSI 转义序列
    device_name=$(printf '%s' "$device_name" | perl -pe 's/\e\[[0-9;]*[A-Za-z]//g')
    case "$device_name" in
        请输入设备名称*)
            device_name=$(printf '%s' "$device_name" | sed -E 's/^请输入设备名称[^:]*:[[:space:]]*//')
            ;;
    esac
    device_name=$(printf '%s' "$device_name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

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
                    "codex": { "enabled": false },
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
            '.tools = (.tools // {}) | .tools[$tool] = ((.tools[$tool] // {}) + {enabled: $enabled})' "$target" > "${target}.tmp"
        mv "${target}.tmp" "$target"
    fi
}

# 通用的 hooks 合并函数
# 合并策略：
# 1. 保留用户现有的非 cc-notify hooks
# 2. 对模板中声明的事件，替换当前由 cc-notify 管理的 hooks
# 3. 保留用户配置中的其他事件和其他顶层字段
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

    jq --slurpfile tmpl "$template" '
        def is_managed_hook_entry:
            ((.command? // "") | contains(".cc-notify/bin/smart-notify.sh"))
            or (([.hooks[]?.command? // empty] | any(. | contains(".cc-notify/bin/smart-notify.sh"))));

        def merge_event_hooks($existing; $managed):
            (($existing // []) | map(select(is_managed_hook_entry | not))) + ($managed // []);

        def strip_managed_hooks($hooks):
            ($hooks // {})
            | with_entries(
                .value = ((.value // []) | map(select(is_managed_hook_entry | not)))
            )
            | with_entries(select((.value | length) > 0));

        def merge_all_hooks($user_hooks; $template_hooks):
            reduce ($template_hooks | keys_unsorted[]) as $event_name
                ($user_hooks;
                    .[$event_name] = merge_event_hooks($user_hooks[$event_name]; $template_hooks[$event_name])
                );

        . as $current |
        ($tmpl[0]) as $template |
        (strip_managed_hooks($current.hooks)) as $user_hooks |
        ($template.hooks // {}) as $template_hooks |
        ($current + ($template | del(.hooks))) + {hooks: merge_all_hooks($user_hooks; $template_hooks)}
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

strip_managed_hooks_from_config() {
    local target="$1"

    [ -f "$target" ] || return 0

    if ! jq empty "$target" 2>/dev/null; then
        log_warning "OpenCode: 旧配置格式错误，跳过 hooks 清理"
        return 1
    fi

    local tmp_file="${target}.tmp"

    jq '
        def is_managed_hook_entry:
            ((.command? // "") | contains(".cc-notify/bin/smart-notify.sh"))
            or (([.hooks[]?.command? // empty] | any(. | contains(".cc-notify/bin/smart-notify.sh"))));

        if (.hooks? | type) == "object" then
            .hooks = (
                .hooks
                | with_entries(
                    .value = ((.value // []) | map(select(is_managed_hook_entry | not)))
                )
                | with_entries(select((.value | length) > 0))
            )
            | if (.hooks | length) == 0 then del(.hooks) else . end
        else
            .
        end
    ' "$target" > "$tmp_file"

    if [ $? -eq 0 ] && [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$target"
    else
        rm -f "$tmp_file"
        return 1
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

    merge_hooks_config "$target" "$template" "Claude Code"
    local result=$?

    if [ $result -eq 0 ]; then
        cleanup_legacy_claude_hook_script
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

# 写入 OpenCode 插件（官方插件机制）
write_opencode_hooks() {
    local templates_dir
    templates_dir=$(get_templates_dir)
    local template="$templates_dir/opencode-plugin.js"
    local plugin_dir="$HOME/.config/opencode/plugins"
    local target="$plugin_dir/cc-notify.js"
    local legacy_config="$HOME/.config/opencode/opencode.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    ensure_dir "$plugin_dir"
    backup_file "$target"
    cp "$template" "$target"
    log_success "OpenCode: $target (已安装官方插件)"

    if [ -f "$legacy_config" ]; then
        backup_file "$legacy_config"
        if strip_managed_hooks_from_config "$legacy_config"; then
            log_info "OpenCode: 已清理旧版 hooks 配置"
        fi
    fi

    update_tool_status "opencode" "true"
    return 0
}

ensure_codex_feature_enabled() {
    local target="$HOME/.codex/config.toml"

    ensure_dir "$(dirname "$target")"

    if [ ! -f "$target" ]; then
        cat > "$target" <<'EOF'
[features]
codex_hooks = true
EOF
        log_success "Codex: $target (已创建并启用 hooks)"
        return 0
    fi

    backup_file "$target"

    if grep -Eq '^[[:space:]]*codex_hooks[[:space:]]*=' "$target"; then
        perl -0pi -e 's/^[ \t]*codex_hooks[ \t]*=.*/codex_hooks = true/mg' "$target"
        log_success "Codex: 已启用 codex_hooks"
        return 0
    fi

    if grep -Eq '^[[:space:]]*\[features\][[:space:]]*$' "$target"; then
        perl -0pi -e 's/^\[features\]\s*$/[features]\ncodex_hooks = true/m' "$target"
        log_success "Codex: 已在 [features] 中启用 codex_hooks"
        return 0
    fi

    cat >> "$target" <<'EOF'

[features]
codex_hooks = true
EOF
    log_success "Codex: 已追加 hooks feature 配置"
}

cleanup_legacy_claude_hook_script() {
    local legacy_script="$HOME/.claude/hooks/smart-notify.sh"

    [ -f "$legacy_script" ] || return 0

    if grep -q "智能通知脚本 - 简化可靠版" "$legacy_script" 2>/dev/null || \
       grep -q "核心逻辑：锁屏必发" "$legacy_script" 2>/dev/null; then
        backup_file "$legacy_script"
        rm -f "$legacy_script"
        log_info "Claude Code: 已清理旧版 ~/.claude/hooks/smart-notify.sh"
    fi
}

write_codex_hooks() {
    local templates_dir
    templates_dir=$(get_templates_dir)
    local template="$templates_dir/codex-hooks.json"
    local target="$HOME/.codex/hooks.json"

    if [ ! -f "$template" ]; then
        log_error "模板文件不存在: $template"
        return 1
    fi

    ensure_codex_feature_enabled || return 1
    merge_hooks_config "$target" "$template" "Codex"
    local result=$?

    if [ $result -eq 0 ]; then
        update_tool_status "codex" "true"
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
    local lib_dir
    lib_dir=$(get_lib_dir)
    local target_dir="$HOME/.cc-notify/bin"

    ensure_dir "$target_dir"

    cp "$lib_dir/notify.sh" "$target_dir/smart-notify.sh"
    chmod +x "$target_dir/smart-notify.sh"

    log_success "通知脚本: $target_dir/smart-notify.sh"
}
