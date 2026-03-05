#!/bin/bash
# cc-notify 智能通知核心脚本
# 核心设计：只在用户真正需要时才打扰

# 参数
TITLE="${1:-AI通知}"
BODY="${2:-需要关注}"
PRIORITY="${3:-normal}"  # high / normal / low

# 配置文件路径
CONFIG_FILE="$HOME/.cc-notify/config.json"

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

    if [ -z "$BARK_KEY" ] || [ "$BARK_KEY" = "null" ]; then
        echo "错误: Bark Key 未配置" >&2
        exit 1
    fi

    # 默认 URL
    BARK_URL="${BARK_URL:-https://api.day.app}"
    debug_log "配置加载成功: BARK_URL=$BARK_URL"
}

# URL 编码
url_encode() {
    local str="$1"
    echo "$str" | jq -sRr @uri
}

# 发送通知
send_notification() {
    local encoded_title=$(url_encode "$TITLE")
    local encoded_body=$(url_encode "$BODY")

    # 根据优先级设置级别
    local level=""
    case "$PRIORITY" in
        high)
            level="&level=timeSensitive"
            ;;
        low)
            level="&level=active"
            ;;
    esac

    local url="${BARK_URL}/${BARK_KEY}/${encoded_title}/${encoded_body}?group=cc-notify${level}"

    debug_log "发送通知: $url"
    local response=$(curl -s "$url")
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
            *"/Xcode.app"|*"/Sublime"*|*"/Atom.app"|*"/Zed.app")
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
            dev.zed.Zed)
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
       [[ "$proc_name" == *"Zed"* ]]; then
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

    # 判断是否发送
    if should_notify; then
        send_notification
    fi
}

main
