#!/bin/bash
# cc-notify 智能通知核心脚本
# 核心设计：只在用户真正需要时才打扰

# 参数
TITLE="${1:-AI通知}"
BODY="${2:-需要关注}"
PRIORITY="${3:-normal}"  # high / normal / low

# 配置文件路径
CONFIG_FILE="$HOME/.cc-notify/config.json"
# 锁文件目录
LOCK_DIR="$HOME/.cc-notify/locks"
# 去重时间窗口（秒）- 同一通知在窗口内只发送一次
DEDUP_WINDOW="${CC_NOTIFY_DEDUP_WINDOW:-60}"

# 调试模式（设置 CC_NOTIFY_DEBUG=1 开启）
[ "$CC_NOTIFY_DEBUG" = "1" ] && DEBUG="true" || DEBUG="false"

debug_log() {
    [ "$DEBUG" = "true" ] && echo "[DEBUG] $1" >&2
}

# 读取配置
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "错误: 配置文件不存在，请先运行 install.sh" >&2
        exit 1
    fi

    # 检查 jq 是否存在
    if ! command -v jq &>/dev/null; then
        echo "错误: 需要安装 jq，请运行: brew install jq" >&2
        exit 1
    fi

    BARK_KEY=$(jq -r '.bark.key' "$CONFIG_FILE" 2>/dev/null)
    BARK_URL=$(jq -r '.bark.url' "$CONFIG_FILE" 2>/dev/null)
    DEVICE_NAME=$(jq -r '.device.name // empty' "$CONFIG_FILE" 2>/dev/null)

    if [ -z "$BARK_KEY" ] || [ "$BARK_KEY" = "null" ]; then
        echo "错误: Bark Key 未配置" >&2
        exit 1
    fi

    # 默认 URL
    BARK_URL="${BARK_URL:-https://api.day.app}"

    # 如果没有配置设备名称，使用主机名
    if [ -z "$DEVICE_NAME" ] || [ "$DEVICE_NAME" = "null" ]; then
        DEVICE_NAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "Unknown")
    fi

    debug_log "配置加载成功: BARK_URL=$BARK_URL, DEVICE=$DEVICE_NAME"
}

# 获取当前终端名称
get_terminal_name() {
    # 尝试从环境变量获取
    if [ -n "$TERM_PROGRAM" ]; then
        echo "$TERM_PROGRAM"
        return
    fi

    # 尝试从父进程获取
    local parent_cmd=$(ps -o comm= -p $PPID 2>/dev/null)
    if [ -n "$parent_cmd" ]; then
        case "$parent_cmd" in
            *iTerm*) echo "iTerm" ;;
            *Terminal*) echo "Terminal" ;;
            *kitty*) echo "Kitty" ;;
            *warp*) echo "Warp" ;;
            *alacritty*) echo "Alacritty" ;;
            *cursor*) echo "Cursor" ;;
            *code*) echo "VSCode" ;;
            *) echo "$parent_cmd" ;;
        esac
        return
    fi

    echo "Terminal"
}

# 生成通知唯一标识（用于去重）
get_notify_hash() {
    echo "${TITLE}||${BODY}" | shasum -a 256 | cut -d' ' -f1
}

# 使用文件锁进行原子去重
# 返回 0 表示可以发送，返回 1 表示已被其他实例发送
try_acquire_lock() {
    local hash=$(get_notify_hash)
    local lock_file="$LOCK_DIR/${hash}.lock"
    local now=$(date +%s)

    # 创建锁目录
    mkdir -p "$LOCK_DIR" 2>/dev/null

    # 尝试获取锁（使用 mkdir 作为原子操作）
    if mkdir "$lock_file" 2>/dev/null; then
        # 成功获取锁，写入时间戳
        echo "$now" > "$lock_file/timestamp"
        debug_log "获取锁成功: $hash"
        return 0
    fi

    # 锁已存在，检查是否过期
    local lock_time=$(cat "$lock_file/timestamp" 2>/dev/null || echo "0")
    local age=$((now - lock_time))

    if [ "$age" -gt "$DEDUP_WINDOW" ]; then
        # 锁已过期，强制获取
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

# 释放锁
release_lock() {
    local hash=$(get_notify_hash)
    local lock_file="$LOCK_DIR/${hash}.lock"
    # 延迟释放锁，确保其他实例在窗口期内不会重复发送
    # 锁会在 try_acquire_lock 中过期后自动释放
}

# 清理过期的锁文件
cleanup_expired_locks() {
    local now=$(date +%s)
    local count=0

    # 检查锁目录是否存在
    [ -d "$LOCK_DIR" ] || return 0

    # 使用 find 避免空目录时的通配符问题
    find "$LOCK_DIR" -name "*.lock" -type d 2>/dev/null | while read -r lock_dir; do
        local lock_time=$(cat "$lock_dir/timestamp" 2>/dev/null || echo "0")
        local age=$((now - lock_time))

        if [ "$age" -gt 300 ]; then  # 5分钟以上的锁清理掉
            rm -rf "$lock_dir"
            ((count++))
        fi
    done

    [ "$count" -gt 0 ] && debug_log "清理了 $count 个过期锁"
}

# URL 编码（正确处理换行）
url_encode() {
    local str="$1"
    # 使用 jq 进行 URL 编码，它会正确处理换行符
    echo -n "$str" | jq -sRr @uri
}

# 发送通知
send_notification() {
    # 构建带设备信息的通知内容
    local terminal_name=$(get_terminal_name)
    local source_info="${DEVICE_NAME}"

    if [ -n "$terminal_name" ] && [ "$terminal_name" != "$DEVICE_NAME" ]; then
        source_info="${DEVICE_NAME} · ${terminal_name}"
    fi

    # 使用 POST 请求，body 中使用 \n 字符串作为换行符
    local final_body="${BODY}\\n📍 ${source_info}"

    # 根据优先级设置级别
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

    # 构建 JSON body
    local json_body=$(jq -n \
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
    local response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "$json_body")
    debug_log "响应: $response"
}

# 锁屏检测（macOS）
check_screen_locked() {
    python3 -c "
import Quartz
try:
    d = Quartz.CGSessionCopyCurrentDictionary()
    print('1' if d.get('OnConsoleKey') == 0 else '0')
except Exception as e:
    print('error')
" 2>/dev/null
}

# 获取前台应用信息
# 返回格式: proc_name<TAB>proc_path<TAB>bundle_id
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

# 检查是否是"关注中"的应用（终端/编辑器）
# 使用多种方式匹配：进程名、应用路径、Bundle ID
is_focused_app() {
    local app_info="$1"

    # 使用 tab 字符作为分隔符
    local proc_name proc_path bundle_id
    proc_name=$(echo "$app_info" | cut -f1)
    proc_path=$(echo "$app_info" | cut -f2)
    bundle_id=$(echo "$app_info" | cut -f3)

    debug_log "进程名: [$proc_name]"
    debug_log "应用路径: [$proc_path]"
    debug_log "Bundle ID: [$bundle_id]"

    # ========== 终端应用检测 ==========
    # 1. 通过应用路径匹配（最可靠）
    if [[ -n "$proc_path" ]]; then
        case "$proc_path" in
            *"/iTerm.app"|*"/Terminal.app"|*"/Kitty.app"|*"/Warp.app"| \
            *"/Alacritty.app"|*"/Hyper.app"|*"/WezTerm.app"|*"/Tabby.app")
                debug_log "匹配终端应用（路径）: $proc_path"
                return 0
                ;;
        esac
    fi

    # 2. 通过 Bundle ID 匹配
    if [[ -n "$bundle_id" ]]; then
        case "$bundle_id" in
            com.googlecode.iterm2|com.apple.Terminal| \
            com.kittyapp|dev.warp.Warp-Stable|io.alacritty|co.zeit.hyper)
            debug_log "匹配终端应用（Bundle ID）: $bundle_id"
            return 0
            ;;
        esac
    fi

    # 3. 通过进程名匹配（兜底）
    case "$proc_name" in
        *iTerm*|*Terminal*|*Kitty*|*Warp*|*Alacritty*|*Hyper*|*WezTerm*)
            debug_log "匹配终端应用（进程名）: $proc_name"
            return 0
            ;;
    esac

    # ========== 编辑器/IDE 应用检测 ==========
    # 1. 通过应用路径匹配（最可靠）
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

    # 2. 通过 Bundle ID 匹配
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

    # 3. 通过进程名匹配（兜底）
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

    # ========== 特殊处理：Electron 应用 ==========
    # 如果进程名是 Electron，检查路径是否包含已知编辑器
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

# 判断是否应该发送通知
should_notify() {
    # 1. 检查锁屏
    local screen_locked=$(check_screen_locked)
    debug_log "锁屏状态: $screen_locked"

    if [ "$screen_locked" = "1" ]; then
        debug_log "锁屏中，发送通知"
        return 0
    fi

    if [ "$screen_locked" = "error" ]; then
        debug_log "锁屏检测失败，继续其他检测"
    fi

    # 2. 获取前台应用信息
    local app_info=$(get_frontmost_app_info)

    if [ -z "$app_info" ]; then
        echo "警告: 未授权辅助功能权限，无法检测前台应用" >&2
        echo "请在 系统设置 → 隐私与安全 → 辅助功能 中授权" >&2
        # 没有权限时，默认发送通知
        return 0
    fi

    debug_log "应用信息: [$app_info]"

    # 3. 高优先级：等待5秒后再次检查
    if [ "$PRIORITY" = "high" ]; then
        debug_log "高优先级通知，等待5秒..."
        sleep 5

        # 5秒后再次检查锁屏
        screen_locked=$(check_screen_locked)
        if [ "$screen_locked" = "1" ]; then
            debug_log "5秒后检测到锁屏，发送通知"
            return 0
        fi

        # 5秒后再次检查前台应用
        app_info=$(get_frontmost_app_info)
        if [ -z "$app_info" ]; then
            debug_log "无辅助功能权限，发送高优先级通知"
            return 0
        fi

        if is_focused_app "$app_info"; then
            debug_log "5秒后用户仍在关注，不发送"
            return 1
        fi

        debug_log "5秒后用户已离开，发送通知"
        return 0
    fi

    # 4. 检查是否在关注中
    if is_focused_app "$app_info"; then
        debug_log "用户在关注中，不发送通知"
        return 1
    fi

    # 其他应用，发送通知
    debug_log "用户不在关注，发送通知"
    return 0
}

# 主函数
main() {
    # 加载配置
    load_config

    # 高优先级通知（需要用户介入）跳过去重，直接发送
    if [ "$PRIORITY" = "high" ]; then
        debug_log "高优先级通知（需要用户介入），跳过去重"
        if should_notify; then
            send_notification
        fi
        exit 0
    fi

    # 清理过期锁
    cleanup_expired_locks

    # 尝试获取锁（原子去重）- 只对 normal/low 优先级的通知去重
    if ! try_acquire_lock; then
        debug_log "通知被去重拦截（其他实例已发送）"
        exit 0
    fi

    # 判断是否发送
    if should_notify; then
        send_notification
    fi
}

main
