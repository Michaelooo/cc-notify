#!/bin/bash
# cc-notify 一键安装脚本
# 使用方式: curl -fsSL https://raw.githubusercontent.com/USER/cc-notify/main/install.sh | bash

set -e

# 脚本版本
VERSION="1.0.0"

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共函数
source "$SCRIPT_DIR/lib/common.sh" 2>/dev/null || {
    echo "❌ 无法加载公共函数库"
    exit 1
}

# 加载其他模块
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/configure.sh"

# 检查依赖
check_dependencies() {
    print_step "1" "5" "🔍 检查依赖"

    local missing=()

    if ! command_exists jq; then
        missing+=("jq")
    fi

    if ! command_exists python3; then
        missing+=("python3")
    fi

    if ! command_exists curl; then
        missing+=("curl")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
        echo ""
        echo "请运行以下命令安装依赖:"
        echo "  brew install ${missing[*]}"
        exit 1
    fi

    log_success "依赖完整"
}

# 检测 AI 工具
detect_ai_tools() {
    print_step "2" "5" "🔍 检测已安装的 AI 工具"

    DETECTION_RESULT=$(detect_all)
    print_detection_result "$DETECTION_RESULT"
}

# 配置 Bark
configure_bark() {
    print_step "3" "5" "📱 配置 Bark 通知"

    if [ -n "$BARK_KEY" ]; then
        log_info "检测到环境变量 BARK_KEY"
        INPUT_BARK_KEY="$BARK_KEY"
    else
        echo ""
        echo "请输入你的 Bark Key（在 Bark App 中查看）:"
        read -p "  Bark Key: " INPUT_BARK_KEY
    fi

    if [ -z "$INPUT_BARK_KEY" ]; then
        log_error "Bark Key 不能为空"
        exit 1
    fi

    echo ""
    log_info "发送测试通知..."
    local test_url="https://api.day.app/${INPUT_BARK_KEY}/cc-notify/安装测试成功?group=cc-notify"
    local response=$(curl -s "$test_url")

    if echo "$response" | grep -q "success\|200"; then
        log_success "Bark 配置成功，请查看手机是否收到测试通知"
    else
        log_warning "Bark 可能配置失败，请检查 Key 是否正确"
        if ! confirm "是否继续安装？" "N"; then
            exit 1
        fi
    fi
}

# 选择要配置的工具
select_tools() {
    print_step "4" "5" "⚙️  选择要配置的工具"

    local claude=$(echo "$DETECTION_RESULT" | jq -r '.["claude-code"]')
    local cursor=$(echo "$DETECTION_RESULT" | jq -r '.cursor')
    local opencode=$(echo "$DETECTION_RESULT" | jq -r '.opencode')

    ENABLE_CLAUDE="false"
    ENABLE_CURSOR="false"
    ENABLE_OPENCODE="false"

    echo ""

    if [ "$claude" = "installed" ]; then
        if confirm "配置 Claude Code?"; then
            ENABLE_CLAUDE="true"
        fi
    else
        log_info "跳过 Claude Code（未安装）"
    fi

    if [ "$cursor" = "installed" ]; then
        if confirm "配置 Cursor?"; then
            ENABLE_CURSOR="true"
        fi
    else
        log_info "跳过 Cursor（未安装）"
    fi

    if [ "$opencode" = "installed" ]; then
        if confirm "配置 OpenCode?"; then
            ENABLE_OPENCODE="true"
        fi
    else
        log_info "跳过 OpenCode（未安装）"
    fi

    if [ "$ENABLE_CLAUDE" = "false" ] && [ "$ENABLE_CURSOR" = "false" ] && [ "$ENABLE_OPENCODE" = "false" ]; then
        log_error "请至少选择一个工具进行配置"
        exit 1
    fi
}

# 执行安装
do_install() {
    print_step "5" "5" "📝 写入配置"

    ensure_dir "$HOME/.cc-notify/bin"
    ensure_dir "$HOME/.cc-notify/lib"

    write_user_config "$INPUT_BARK_KEY"
    install_notify_script

    if [ "$ENABLE_CLAUDE" = "true" ]; then
        merge_claude_hooks
    fi

    if [ "$ENABLE_CURSOR" = "true" ]; then
        write_cursor_hooks
    fi

    if [ "$ENABLE_OPENCODE" = "true" ]; then
        write_opencode_hooks
    fi

    echo ""
    log_success "安装完成！"
}

# 显示完成信息
show_complete() {
    echo ""
    echo -e "${GREEN}✅ cc-notify v${VERSION} 安装成功！${NC}"
    echo ""
    echo "📋 配置文件位置:"
    echo "   ~/.cc-notify/config.json"
    echo ""
    echo "🧪 测试命令:"
    echo "   ~/.cc-notify/bin/smart-notify.sh '测试' '安装成功' 'normal'"
    echo ""
    echo "⚠️  授权提示:"
    echo "   首次使用请在 系统设置 → 隐私与安全 → 辅助功能 中授权终端应用"
    echo "   这是前台应用检测功能所需的权限"
    echo ""
    echo "📖 更多信息请查看 README.md"
    echo ""
}

# 主流程
main() {
    print_title
    check_dependencies
    detect_ai_tools
    configure_bark
    select_tools
    do_install
    show_complete
}

main
