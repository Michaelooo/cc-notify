#!/bin/bash
# cc-notify 智能通知核心脚本
# 设计目标：
# 1. 需要用户介入时尽快通知
# 2. 尽量利用 hooks 的上下文，避免把过程态误报成终态
# 3. 保持对 Claude Code、OpenCode、Cursor 及后续工具的扩展能力

TITLE="AI通知"
BODY="需要关注"
PRIORITY="normal" # high / normal / low
SOURCE="manual"
EVENT_NAME=""
EVENT_KIND=""
EVENT_SUBTYPE=""

CONFIG_FILE="$HOME/.cc-notify/config.json"
LOCK_DIR="$HOME/.cc-notify/locks"
DEDUP_WINDOW="${CC_NOTIFY_DEDUP_WINDOW:-}"
RECHECK_SECONDS="${CC_NOTIFY_RECHECK_SECONDS:-5}"

[ "${CC_NOTIFY_DEBUG:-0}" = "1" ] && DEBUG="true" || DEBUG="false"
[ "${CC_NOTIFY_DRY_RUN:-0}" = "1" ] && DRY_RUN="true" || DRY_RUN="false"
[ "${CC_NOTIFY_FORCE_NOTIFY:-0}" = "1" ] && FORCE_NOTIFY="true" || FORCE_NOTIFY="false"

HOOK_INPUT=""
HOOK_JSON="false"
SKIP_NOTIFY="false"
SKIP_REASON=""

BARK_KEY=""
BARK_URL=""
DEVICE_NAME=""
DEDUP_ENABLED="true"
SMART_DETECT_ENABLED="true"

HOOK_EVENT_NAME=""
NOTIFICATION_TYPE=""
HOOK_MESSAGE=""
HOOK_TITLE=""
HOOK_ERROR=""
HOOK_REASON=""
HOOK_TOOL_NAME=""
HOOK_TASK_SUBJECT=""
HOOK_LAST_ASSISTANT_MESSAGE=""
HOOK_IS_INTERRUPT="false"
HOOK_ELICITATION_SOURCE=""
HOOK_ELICITATION_URL=""
HOOK_TOOL_RESPONSE_RAW=""
HOOK_TOOL_RESPONSE_TEXT=""
HOOK_TOOL_EXIT_CODE=""

debug_log() {
    [ "$DEBUG" = "true" ] && echo "[DEBUG] $1" >&2
}

is_truthy() {
    case "$1" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

source_label() {
    case "$SOURCE" in
        claude-code)
            echo "Claude Code"
            ;;
        opencode)
            echo "OpenCode"
            ;;
        codex)
            echo "Codex"
            ;;
        cursor)
            echo "Cursor"
            ;;
        *)
            echo "$SOURCE"
            ;;
    esac
}

normalize_app_name() {
    local raw="$1"
    local name=""

    [ -n "$raw" ] || return 1

    name=$(basename "$raw")
    name="${name%.app}"

    case "$name" in
        iTerm2|iTerm)
            printf 'iTerm'
            ;;
        Apple_Terminal|Terminal|zsh|bash|sh|fish)
            printf 'Terminal'
            ;;
        kitty|Kitty)
            printf 'Kitty'
            ;;
        Warp|warp)
            printf 'Warp'
            ;;
        Alacritty|alacritty)
            printf 'Alacritty'
            ;;
        Hyper|hyper)
            printf 'Hyper'
            ;;
        WezTerm|wezterm|wezterm-gui)
            printf 'WezTerm'
            ;;
        Tabby|tabby)
            printf 'Tabby'
            ;;
        Cursor)
            printf 'Cursor'
            ;;
        Code|code|VSCodium|codium)
            printf 'VSCode'
            ;;
        *)
            return 1
            ;;
    esac
}

trim_text() {
    local text="$1"
    text="${text#"${text%%[![:space:]]*}"}"
    text="${text%"${text##*[![:space:]]}"}"
    printf '%s' "$text"
}

sanitize_line() {
    local text="$1"
    text=$(printf '%s' "$text" | tr '\n' ' ' | tr '\r' ' ')
    text=$(printf '%s' "$text" | sed 's/[[:space:]][[:space:]]*/ /g')
    trim_text "$text"
}

truncate_text() {
    local text
    text=$(sanitize_line "$1")
    local limit="${2:-160}"

    if [ ${#text} -le "$limit" ]; then
        printf '%s' "$text"
        return
    fi

    printf '%s…' "${text:0:$((limit - 1))}"
}

join_lines() {
    local result=""
    local line=""

    for line in "$@"; do
        line=$(trim_text "$line")
        [ -n "$line" ] || continue

        if [ -n "$result" ]; then
            result="${result}"$'\n'"${line}"
        else
            result="$line"
        fi
    done

    printf '%s' "$result"
}

json_get() {
    local query="$1"
    printf '%s' "$HOOK_INPUT" | jq -r "$query // empty" 2>/dev/null
}

json_get_compact() {
    local query="$1"
    printf '%s' "$HOOK_INPUT" | jq -c "$query // empty" 2>/dev/null
}

read_hook_input() {
    if [ -t 0 ]; then
        return
    fi

    HOOK_INPUT=$(cat)
    [ -n "$HOOK_INPUT" ] || return

    if printf '%s' "$HOOK_INPUT" | jq empty >/dev/null 2>&1; then
        HOOK_JSON="true"
        debug_log "检测到 hook JSON 输入"
    else
        debug_log "stdin 存在，但不是 JSON，按普通命令模式处理"
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --source)
                SOURCE="$2"
                shift 2
                ;;
            --event)
                EVENT_NAME="$2"
                shift 2
                ;;
            --kind)
                EVENT_KIND="$2"
                shift 2
                ;;
            --subtype)
                EVENT_SUBTYPE="$2"
                shift 2
                ;;
            --title)
                TITLE="$2"
                shift 2
                ;;
            --body)
                BODY="$2"
                shift 2
                ;;
            --priority)
                PRIORITY="$2"
                shift 2
                ;;
            --help)
                cat <<'EOF'
Usage:
  smart-notify.sh [title] [body] [priority]
  smart-notify.sh --source claude-code
  smart-notify.sh --source cursor --event stop --kind terminal --title "..." --body "..." --priority low
EOF
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done

    if [ $# -gt 0 ]; then
        TITLE="${1:-$TITLE}"
        BODY="${2:-$BODY}"
        PRIORITY="${3:-$PRIORITY}"
    fi
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "错误: 配置文件不存在，请先运行 install.sh" >&2
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "错误: 需要安装 jq，请运行: brew install jq" >&2
        exit 1
    fi

    BARK_KEY=$(jq -r '.bark.key' "$CONFIG_FILE" 2>/dev/null)
    BARK_URL=$(jq -r '.bark.url // "https://api.day.app"' "$CONFIG_FILE" 2>/dev/null)
    DEVICE_NAME=$(jq -r '.device.name // empty' "$CONFIG_FILE" 2>/dev/null)
    DEDUP_ENABLED=$(jq -r '.dedup.enabled // true' "$CONFIG_FILE" 2>/dev/null)
    SMART_DETECT_ENABLED=$(jq -r '.smart_detect.enabled // true' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$DEDUP_WINDOW" ]; then
        DEDUP_WINDOW=$(jq -r '.dedup.window_seconds // 60' "$CONFIG_FILE" 2>/dev/null)
    fi

    if [ -z "$BARK_KEY" ] || [ "$BARK_KEY" = "null" ]; then
        echo "错误: Bark Key 未配置" >&2
        exit 1
    fi

    if [ -z "$DEVICE_NAME" ] || [ "$DEVICE_NAME" = "null" ]; then
        DEVICE_NAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "Unknown")
    fi

    debug_log "配置加载成功: BARK_URL=$BARK_URL, DEVICE=$DEVICE_NAME, DEDUP_WINDOW=$DEDUP_WINDOW"
}

get_terminal_name() {
    local normalized=""

    if [ -n "${TERM_PROGRAM:-}" ]; then
        if normalized=$(normalize_app_name "$TERM_PROGRAM" 2>/dev/null); then
            echo "$normalized"
            return
        fi
    fi

    local parent_cmd
    parent_cmd=$(ps -o comm= -p "$PPID" 2>/dev/null)
    if [ -n "$parent_cmd" ]; then
        if normalized=$(normalize_app_name "$parent_cmd" 2>/dev/null); then
            echo "$normalized"
            return
        fi

        case "$parent_cmd" in
            *iTerm*)
                echo "iTerm"
                ;;
            *Terminal*)
                echo "Terminal"
                ;;
            *kitty*)
                echo "Kitty"
                ;;
            *warp*)
                echo "Warp"
                ;;
            *alacritty*)
                echo "Alacritty"
                ;;
            *cursor*)
                echo "Cursor"
                ;;
            *code*)
                echo "VSCode"
                ;;
            *)
                echo "Terminal"
                ;;
        esac
        return
    fi

    echo "Terminal"
}

build_hook_dedup_subject() {
    case "$EVENT_NAME" in
        PermissionRequest)
            join_lines "$HOOK_TOOL_NAME" "$(json_get '.tool_input.command')" "$(json_get '.tool_input.file_path')"
            ;;
        Notification)
            join_lines "$NOTIFICATION_TYPE" "${HOOK_MESSAGE:-$HOOK_TITLE}"
            ;;
        Elicitation)
            join_lines "$HOOK_MESSAGE" "$HOOK_ELICITATION_SOURCE" "$HOOK_ELICITATION_URL"
            ;;
        StopFailure)
            join_lines "$HOOK_ERROR" "$HOOK_REASON" "${HOOK_MESSAGE:-$HOOK_TITLE}"
            ;;
        TaskCompleted)
            join_lines "$HOOK_TASK_SUBJECT"
            ;;
        SessionEnd)
            join_lines "$HOOK_REASON"
            ;;
        PostToolUse|PostToolUseFailure)
            join_lines "$HOOK_TOOL_NAME" "$HOOK_ERROR" "$HOOK_TOOL_EXIT_CODE" "$HOOK_TOOL_RESPONSE_TEXT"
            ;;
        Stop)
            join_lines "$HOOK_LAST_ASSISTANT_MESSAGE"
            ;;
        *)
            join_lines "$HOOK_TITLE" "$HOOK_MESSAGE" "$HOOK_ERROR" "$HOOK_REASON"
            ;;
    esac
}

get_notify_fingerprint() {
    if [ "$HOOK_JSON" = "true" ]; then
        printf '%s' "hook||${EVENT_NAME}||${EVENT_SUBTYPE}||$(sanitize_line "$(build_hook_dedup_subject)")"
        return
    fi

    printf '%s' "${SOURCE}||${EVENT_NAME}||${EVENT_SUBTYPE}||${TITLE}||${BODY}"
}

get_notify_hash() {
    get_notify_fingerprint | shasum -a 256 | cut -d' ' -f1
}

try_acquire_lock() {
    if ! is_truthy "$DEDUP_ENABLED"; then
        debug_log "去重已关闭"
        return 0
    fi

    local hash
    hash=$(get_notify_hash)
    local lock_file="$LOCK_DIR/${hash}.lock"
    local now
    now=$(date +%s)

    mkdir -p "$LOCK_DIR" 2>/dev/null

    if mkdir "$lock_file" 2>/dev/null; then
        echo "$now" > "$lock_file/timestamp"
        debug_log "获取锁成功: $hash"
        return 0
    fi

    local lock_time
    lock_time=$(cat "$lock_file/timestamp" 2>/dev/null || echo "0")
    local age=$((now - lock_time))

    if [ "$age" -gt "$DEDUP_WINDOW" ]; then
        rm -rf "$lock_file" 2>/dev/null
        if mkdir "$lock_file" 2>/dev/null; then
            echo "$now" > "$lock_file/timestamp"
            debug_log "锁已过期，重新获取: $hash"
            return 0
        fi
    fi

    debug_log "锁被占用，跳过发送 (已锁定 ${age}秒)"
    return 1
}

cleanup_expired_locks() {
    local now
    now=$(date +%s)
    local count=0
    local lock_dir=""

    [ -d "$LOCK_DIR" ] || return 0

    while IFS= read -r lock_dir; do
        [ -n "$lock_dir" ] || continue

        local lock_time
        lock_time=$(cat "$lock_dir/timestamp" 2>/dev/null || echo "0")
        local age=$((now - lock_time))

        if [ "$age" -gt 300 ]; then
            rm -rf "$lock_dir"
            count=$((count + 1))
        fi
    done < <(find "$LOCK_DIR" -name "*.lock" -type d 2>/dev/null)

    [ "$count" -gt 0 ] && debug_log "清理了 $count 个过期锁"
}

send_notification() {
    local terminal_name
    terminal_name=$(get_terminal_name)
    local source_info="${DEVICE_NAME}"

    if [ -n "$terminal_name" ] && [ "$terminal_name" != "$DEVICE_NAME" ]; then
        source_info="${DEVICE_NAME} · ${terminal_name}"
    fi

    local final_body
    final_body=$(join_lines "$BODY" "📍 ${source_info}")

    local level=""
    case "$PRIORITY" in
        high)
            level="timeSensitive"
            ;;
        low)
            level="active"
            ;;
        *)
            level=""
            ;;
    esac

    local json_body
    json_body=$(jq -n \
        --arg title "$TITLE" \
        --arg body "$final_body" \
        --arg group "cc-notify" \
        --arg level "$level" \
        '{
            title: $title,
            body: $body,
            group: $group
        } + (if $level != "" then {level: $level} else {} end)')

    local url="${BARK_URL}/${BARK_KEY}"

    debug_log "发送通知 (POST): $url"
    debug_log "内容: $json_body"

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY RUN] $json_body" >&2
        return 0
    fi

    local response
    response=$(curl -sS --max-time 10 -X POST "$url" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "$json_body")
    debug_log "响应: $response"
}

check_screen_locked() {
    python3 -c "
import Quartz
try:
    session = Quartz.CGSessionCopyCurrentDictionary()
    print('1' if session.get('OnConsoleKey') == 0 else '0')
except Exception:
    print('error')
" 2>/dev/null
}

get_frontmost_app_info() {
    osascript -e '
tell application "System Events"
    set proc to first application process whose frontmost is true
    set procName to name of proc
    try
        set procPath to POSIX path of application file of proc
    on error
        set procPath to ""
    end try
    try
        set bundleId to bundle identifier of proc
    on error
        set bundleId to ""
    end try
    return procName & tab & procPath & tab & bundleId
end tell
' 2>/dev/null
}

is_focused_app() {
    local app_info="$1"
    local proc_name proc_path bundle_id

    proc_name=$(printf '%s' "$app_info" | cut -f1)
    proc_path=$(printf '%s' "$app_info" | cut -f2)
    bundle_id=$(printf '%s' "$app_info" | cut -f3)

    debug_log "进程名: [$proc_name]"
    debug_log "应用路径: [$proc_path]"
    debug_log "Bundle ID: [$bundle_id]"

    if [[ -n "$proc_path" ]]; then
        case "$proc_path" in
            *"/iTerm.app"|*"/Terminal.app"|*"/Kitty.app"|*"/Warp.app"| \
            *"/Alacritty.app"|*"/Hyper.app"|*"/WezTerm.app"|*"/Tabby.app")
                debug_log "匹配终端应用（路径）: $proc_path"
                return 0
                ;;
        esac
    fi

    if [[ -n "$bundle_id" ]]; then
        case "$bundle_id" in
            com.googlecode.iterm2|com.apple.Terminal| \
            com.kittyapp|dev.warp.Warp-Stable|io.alacritty|co.zeit.hyper)
                debug_log "匹配终端应用（Bundle ID）: $bundle_id"
                return 0
                ;;
        esac
    fi

    case "$proc_name" in
        *iTerm*|*Terminal*|*Kitty*|*Warp*|*Alacritty*|*Hyper*|*WezTerm*)
            debug_log "匹配终端应用（进程名）: $proc_name"
            return 0
            ;;
    esac

    if [[ -n "$proc_path" ]]; then
        case "$proc_path" in
            *"/Cursor.app"|*"/Code.app"|*"/Visual Studio Code.app"| \
            *"/IntelliJ"*|*"/WebStorm.app"|*"/PyCharm.app"| \
            *"/GoLand.app"|*"/CLion.app"|*"/Android Studio"*| \
            *"/Xcode.app"|*"/Sublime"*|*"/Atom.app"|*"/Zed.app"| \
            *"/Obsidian.app")
                debug_log "匹配编辑器应用（路径）: $proc_path"
                return 0
                ;;
        esac
    fi

    if [[ -n "$bundle_id" ]]; then
        case "$bundle_id" in
            com.todesktop.*|com.microsoft.VSCode|com.jetbrains.*| \
            com.apple.dt.Xcode|com.sublimetext.*|com.github.atom| \
            dev.zed.Zed|md.obsidian)
                debug_log "匹配编辑器应用（Bundle ID）: $bundle_id"
                return 0
                ;;
        esac
    fi

    if [[ "$proc_name" == *"Cursor"* ]] || \
       [[ "$proc_name" == *"Code"* ]] || \
       [[ "$proc_name" == *"IntelliJ"* ]] || \
       [[ "$proc_name" == *"WebStorm"* ]] || \
       [[ "$proc_name" == *"PyCharm"* ]] || \
       [[ "$proc_name" == *"GoLand"* ]] || \
       [[ "$proc_name" == *"CLion"* ]] || \
       [[ "$proc_name" == *"Android Studio"* ]] || \
       [[ "$proc_name" == *"Xcode"* ]] || \
       [[ "$proc_name" == *"Sublime"* ]] || \
       [[ "$proc_name" == *"Atom"* ]] || \
       [[ "$proc_name" == *"Zed"* ]] || \
       [[ "$proc_name" == *"Obsidian"* ]]; then
        debug_log "匹配编辑器应用（进程名）: $proc_name"
        return 0
    fi

    if [[ "$proc_name" == "Electron" ]] && [[ -n "$proc_path" ]]; then
        case "$proc_path" in
            *Cursor*|*Code*|*VSCode*|*VSCodium*)
                debug_log "Electron 进程匹配到编辑器: $proc_path"
                return 0
                ;;
        esac
    fi

    return 1
}

should_notify() {
    if [ "$FORCE_NOTIFY" = "true" ]; then
        debug_log "强制发送通知"
        return 0
    fi

    if ! is_truthy "$SMART_DETECT_ENABLED"; then
        debug_log "智能检测已关闭，直接发送"
        return 0
    fi

    local screen_locked
    screen_locked=$(check_screen_locked)
    debug_log "锁屏状态: $screen_locked"

    if [ "$screen_locked" = "1" ]; then
        debug_log "锁屏中，发送通知"
        return 0
    fi

    if [ "$screen_locked" = "error" ]; then
        debug_log "锁屏检测失败，继续其他检测"
    fi

    local app_info
    app_info=$(get_frontmost_app_info)

    if [ -z "$app_info" ]; then
        echo "警告: 未授权辅助功能权限，无法检测前台应用" >&2
        echo "请在 系统设置 → 隐私与安全 → 辅助功能 中授权" >&2
        return 0
    fi

    debug_log "应用信息: [$app_info]"

    if [ "$PRIORITY" = "high" ]; then
        if [ "$RECHECK_SECONDS" -gt 0 ] 2>/dev/null; then
            debug_log "高优先级通知，等待 ${RECHECK_SECONDS} 秒后重检..."
            sleep "$RECHECK_SECONDS"
        fi

        screen_locked=$(check_screen_locked)
        if [ "$screen_locked" = "1" ]; then
            debug_log "重检后检测到锁屏，发送通知"
            return 0
        fi

        app_info=$(get_frontmost_app_info)
        if [ -z "$app_info" ]; then
            debug_log "无辅助功能权限，发送高优先级通知"
            return 0
        fi

        if is_focused_app "$app_info"; then
            debug_log "重检后用户仍在关注，不发送"
            return 1
        fi

        debug_log "重检后用户已离开，发送通知"
        return 0
    fi

    if is_focused_app "$app_info"; then
        debug_log "用户在关注中，不发送通知"
        return 1
    fi

    debug_log "用户不在关注，发送通知"
    return 0
}

extract_permission_target() {
    local command=""
    case "$HOOK_TOOL_NAME" in
        Bash)
            command=$(json_get '.tool_input.command')
            [ -n "$command" ] && printf '命令: %s' "$(truncate_text "$command" 120)" && return
            ;;
        Edit|Write|MultiEdit)
            command=$(json_get '.tool_input.file_path')
            [ -n "$command" ] && printf '文件: %s' "$(truncate_text "$command" 120)" && return
            ;;
        *)
            command=$(json_get '.tool_input.file_path')
            [ -n "$command" ] && printf '文件: %s' "$(truncate_text "$command" 120)" && return
            command=$(json_get '.tool_input.command')
            [ -n "$command" ] && printf '命令: %s' "$(truncate_text "$command" 120)" && return
            ;;
    esac

    [ -n "$HOOK_TOOL_NAME" ] && printf '工具: %s' "$HOOK_TOOL_NAME"
}

looks_user_actionable_error() {
    local text
    text=$(printf '%s %s %s %s' "$HOOK_ERROR" "$HOOK_MESSAGE" "$HOOK_REASON" "$HOOK_TOOL_RESPONSE_TEXT" | tr '[:upper:]' '[:lower:]')

    case "$text" in
        *permission\ denied*|*access\ denied*|*not\ authorized*|*not\ authenticated*| \
        *authentication*|*login*|*credential*|*api\ key*|*quota*|*billing*| \
        *rate\ limit*|*network*|*connection\ refused*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

message_needs_user_reply() {
    local text
    text=$(sanitize_line "$1" | tr '[:upper:]' '[:lower:]')
    [ -n "$text" ] || return 1

    case "$text" in
        *"?"*|*"？"*|*please\ provide*|*provide\ more*|*need\ your\ input*|*need\ your\ approval*| \
        *need\ you\ to*|*which\ option*|*choose\ between*|*choose\ one*|*confirm*|*approval*| \
        *authorize*|*log\ in*|*login*|*sign\ in*|*respond\ with*|*reply\ with*|*let\ me\ know*| \
        *"需要你"*|*"请确认"*|*"请选择"*|*"请提供"*|*"请补充"*|*"请告诉我"*|*"是否"*|*"要不要"*|*"告诉我"*|*"补充一下"*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

parse_codex_tool_response() {
    HOOK_TOOL_RESPONSE_RAW=$(json_get_compact '.tool_response')
    HOOK_TOOL_RESPONSE_TEXT=""
    HOOK_TOOL_EXIT_CODE=""

    [ -n "$HOOK_TOOL_RESPONSE_RAW" ] || return

    local payload="$HOOK_TOOL_RESPONSE_RAW"

    if printf '%s' "$payload" | jq -e 'type == "string"' >/dev/null 2>&1; then
        payload=$(printf '%s' "$payload" | jq -r '.')
    fi

    if printf '%s' "$payload" | jq empty >/dev/null 2>&1; then
        HOOK_TOOL_EXIT_CODE=$(printf '%s' "$payload" | jq -r '.exit_code // .exitCode // empty' 2>/dev/null)
        HOOK_TOOL_RESPONSE_TEXT=$(printf '%s' "$payload" | jq -r '
            [
                .error? // empty,
                .stderr? // empty,
                .stdout? // empty,
                .output? // empty
            ]
            | map(select(type == "string" and length > 0))
            | join("\n")
        ' 2>/dev/null)
    else
        HOOK_TOOL_RESPONSE_TEXT="$payload"
    fi

    HOOK_TOOL_RESPONSE_TEXT=$(truncate_text "$HOOK_TOOL_RESPONSE_TEXT" 240)
}

apply_manual_defaults() {
    local label
    label=$(source_label)

    case "$EVENT_KIND" in
        intervention)
            [ "$PRIORITY" = "normal" ] && PRIORITY="high"
            [ "$TITLE" = "AI通知" ] && TITLE="⚠️ 需要你的介入"
            [ "$BODY" = "需要关注" ] && BODY="${label} 需要你回来处理"
            ;;
        terminal)
            [ "$PRIORITY" = "normal" ] && PRIORITY="low"
            [ "$TITLE" = "AI通知" ] && TITLE="✅ ${label} 已停下"
            [ "$BODY" = "需要关注" ] && BODY="请查看当前结果"
            ;;
        error)
            [ "$TITLE" = "AI通知" ] && TITLE="❌ ${label} 遇到错误"
            [ "$BODY" = "需要关注" ] && BODY="请回来看一下"
            ;;
    esac
}

parse_hook_context() {
    HOOK_EVENT_NAME=$(json_get '.hook_event_name')
    [ -n "$HOOK_EVENT_NAME" ] && EVENT_NAME="$HOOK_EVENT_NAME"

    NOTIFICATION_TYPE=$(json_get '.notification_type')
    [ -n "$NOTIFICATION_TYPE" ] && EVENT_SUBTYPE="$NOTIFICATION_TYPE"

    HOOK_MESSAGE=$(json_get '.message')
    HOOK_TITLE=$(json_get '.title')
    HOOK_ERROR=$(json_get '.error')
    HOOK_REASON=$(json_get '.reason')
    HOOK_TOOL_NAME=$(json_get '.tool_name')
    HOOK_TASK_SUBJECT=$(json_get '.task.subject')
    HOOK_LAST_ASSISTANT_MESSAGE=$(json_get '.last_assistant_message')
    HOOK_IS_INTERRUPT=$(json_get '.is_interrupt')
    HOOK_ELICITATION_SOURCE=$(json_get '.source')
    HOOK_ELICITATION_URL=$(json_get '.link')

    [ "$HOOK_IS_INTERRUPT" = "true" ] || HOOK_IS_INTERRUPT="false"

    if [ "$SOURCE" = "codex" ] && [ "$EVENT_NAME" = "PostToolUse" ]; then
        parse_codex_tool_response
    fi

    debug_log "事件: $EVENT_NAME"
    [ -n "$EVENT_SUBTYPE" ] && debug_log "子类型: $EVENT_SUBTYPE"
}

classify_hook_event() {
    local label
    label=$(source_label)

    case "$EVENT_NAME" in
        PermissionRequest)
            EVENT_KIND="intervention"
            PRIORITY="high"
            TITLE="⚠️ 需要权限确认"
            BODY=$(join_lines \
                "${label} 正在等你授权继续" \
                "$(extract_permission_target)")
            ;;
        Notification)
            case "$NOTIFICATION_TYPE" in
                idle_prompt)
                    EVENT_KIND="intervention"
                    PRIORITY="high"
                    TITLE="⏸️ 等待你的输入"
                    BODY=$(join_lines \
                        "${label} 正在等待你补充信息" \
                        "$(truncate_text "${HOOK_MESSAGE:-$HOOK_TITLE}" 180)")
                    ;;
                permission_prompt)
                    EVENT_KIND="intervention"
                    PRIORITY="high"
                    TITLE="⚠️ 需要确认"
                    BODY=$(join_lines \
                        "${label} 正在等待你的确认" \
                        "$(truncate_text "${HOOK_MESSAGE:-$HOOK_TITLE}" 180)")
                    ;;
                elicitation_dialog)
                    EVENT_KIND="intervention"
                    PRIORITY="high"
                    TITLE="📝 需要提供信息"
                    BODY=$(join_lines \
                        "${label} 打开了一个需要你处理的输入请求" \
                        "$(truncate_text "${HOOK_MESSAGE:-$HOOK_TITLE}" 180)")
                    ;;
                auth_success)
                    SKIP_NOTIFY="true"
                    SKIP_REASON="auth_success 不需要手机通知"
                    ;;
                *)
                    SKIP_NOTIFY="true"
                    SKIP_REASON="未配置的 Notification 子类型: $NOTIFICATION_TYPE"
                    ;;
            esac
            ;;
        Elicitation)
            EVENT_KIND="intervention"
            PRIORITY="high"
            TITLE="📝 需要提供信息"
            BODY=$(join_lines \
                "${label} 正在等待你完成输入" \
                "$(truncate_text "$HOOK_MESSAGE" 180)" \
                "$( [ -n "$HOOK_ELICITATION_SOURCE" ] && printf '来源: %s' "$HOOK_ELICITATION_SOURCE" )" \
                "$( [ -n "$HOOK_ELICITATION_URL" ] && printf '链接: %s' "$(truncate_text "$HOOK_ELICITATION_URL" 180)" )")
            ;;
        StopFailure)
            EVENT_KIND="error"
            case "$HOOK_ERROR" in
                authentication_failed|billing_error|invalid_request|permission_error)
                    PRIORITY="high"
                    ;;
                *)
                    PRIORITY="normal"
                    ;;
            esac
            TITLE="❌ ${label} 无法继续"
            BODY=$(join_lines \
                "$( [ -n "$HOOK_ERROR" ] && printf '原因: %s' "$HOOK_ERROR" )" \
                "$(truncate_text "${HOOK_MESSAGE:-$HOOK_TITLE}" 180)")
            ;;
        TaskCompleted)
            EVENT_KIND="terminal"
            PRIORITY="normal"
            TITLE="🎉 任务已完成"
            BODY=$(join_lines \
                "${label} 完成了一个任务" \
                "$(truncate_text "$HOOK_TASK_SUBJECT" 180)")
            ;;
        SessionEnd)
            case "$HOOK_REASON" in
                clear|logout|prompt_input_exit|resume)
                    SKIP_NOTIFY="true"
                    SKIP_REASON="用户主动结束或切换会话: $HOOK_REASON"
                    ;;
                *)
                    EVENT_KIND="terminal"
                    PRIORITY="low"
                    TITLE="✅ 会话已结束"
                    BODY=$(join_lines \
                        "${label} 会话已经结束" \
                        "$( [ -n "$HOOK_REASON" ] && printf '原因: %s' "$HOOK_REASON" )")
                    ;;
            esac
            ;;
        PostToolUse)
            if [ "$SOURCE" = "codex" ]; then
                if [ -n "$HOOK_TOOL_EXIT_CODE" ] && [ "$HOOK_TOOL_EXIT_CODE" = "0" ] && ! looks_user_actionable_error; then
                    SKIP_NOTIFY="true"
                    SKIP_REASON="Codex Bash 成功执行，不通知"
                    return
                fi

                if looks_user_actionable_error; then
                    EVENT_KIND="intervention"
                    PRIORITY="high"
                    TITLE="⚠️ Codex Bash 需要处理"
                    BODY=$(join_lines \
                        "Codex 执行 Bash 后需要你回来处理" \
                        "$( [ -n "$HOOK_TOOL_EXIT_CODE" ] && printf '退出码: %s' "$HOOK_TOOL_EXIT_CODE" )" \
                        "$(truncate_text "$HOOK_TOOL_RESPONSE_TEXT" 180)")
                else
                    SKIP_NOTIFY="true"
                    SKIP_REASON="Codex Bash 失败可能可恢复，默认不通知"
                fi
                return
            fi
            ;;
        PostToolUseFailure)
            if [ "$HOOK_IS_INTERRUPT" = "true" ]; then
                SKIP_NOTIFY="true"
                SKIP_REASON="工具失败来自用户中断"
                return
            fi

            if looks_user_actionable_error; then
                EVENT_KIND="intervention"
                PRIORITY="high"
                TITLE="⚠️ 工具执行需要你处理"
                BODY=$(join_lines \
                    "${label} 遇到了需要人工处理的工具错误" \
                    "$( [ -n "$HOOK_TOOL_NAME" ] && printf '工具: %s' "$HOOK_TOOL_NAME" )" \
                    "$(truncate_text "$HOOK_ERROR" 180)")
            else
                SKIP_NOTIFY="true"
                SKIP_REASON="可恢复工具失败默认不通知"
            fi
            ;;
        Stop)
            if [ "$SOURCE" = "codex" ] && message_needs_user_reply "$HOOK_LAST_ASSISTANT_MESSAGE"; then
                EVENT_KIND="intervention"
                PRIORITY="high"
                TITLE="⏸️ Codex 正在等你回复"
                BODY=$(join_lines \
                    "Codex 当前停在等待你回复的状态" \
                    "$(truncate_text "$HOOK_LAST_ASSISTANT_MESSAGE" 180)")
            else
                EVENT_KIND="terminal"
                PRIORITY="low"
                TITLE="✅ 本轮响应结束"
                BODY=$(join_lines \
                    "${label} 本轮响应已结束" \
                    "$(truncate_text "$HOOK_LAST_ASSISTANT_MESSAGE" 180)")
            fi
            ;;
        *)
            SKIP_NOTIFY="true"
            SKIP_REASON="未识别的 hook 事件: $EVENT_NAME"
            ;;
    esac
}

normalize_priority() {
    case "$PRIORITY" in
        high|normal|low)
            ;;
        *)
            debug_log "未知优先级 [$PRIORITY]，回退为 normal"
            PRIORITY="normal"
            ;;
    esac
}

main() {
    parse_args "$@"
    read_hook_input
    load_config

    if [ "$HOOK_JSON" = "true" ]; then
        parse_hook_context
        classify_hook_event
    else
        apply_manual_defaults
    fi

    if [ "$SKIP_NOTIFY" = "true" ]; then
        debug_log "跳过通知: $SKIP_REASON"
        exit 0
    fi

    normalize_priority

    cleanup_expired_locks
    if ! try_acquire_lock; then
        debug_log "通知被去重拦截"
        exit 0
    fi

    if should_notify; then
        send_notification
    fi
}

main "$@"
