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

# 全局变量
DETECTION_RESULT=""
SELECTED_TOOLS=()
INPUT_BARK_KEY=""

# ============================================================
# 安装步骤
# ============================================================

# 检查依赖
check_dependencies() {
    print_step "1" "5" "检查依赖"

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
        echo "  ${CYAN}brew install ${missing[*]}${NC}"
        exit 1
    fi

    log_success "依赖完整"

    # 检测可选的交互增强工具
    local enhancements=""
    command_exists fzf && enhancements+="fzf "
    command_exists gum && enhancements+="gum "
    if [ -n "$enhancements" ]; then
        log_info "检测到增强工具: ${enhancements}"
    fi
}

# 检测 AI 工具
detect_ai_tools() {
    print_step "2" "5" "检测已安装的 AI 工具"

    DETECTION_RESULT=$(detect_all)

    # 解析检测结果
    local claude=$(echo "$DETECTION_RESULT" | jq -r '.["claude-code"]')
    local cursor=$(echo "$DETECTION_RESULT" | jq -r '.cursor')
    local opencode=$(echo "$DETECTION_RESULT" | jq -r '.opencode')

    echo ""
    if [ "$claude" = "installed" ]; then
        echo -e "  ${GREEN}●${NC} Claude Code   ${DIM}~/.claude/settings.json${NC}"
    else
        echo -e "  ${DIM}○${NC} Claude Code   ${DIM}(未安装)${NC}"
    fi

    if [ "$cursor" = "installed" ]; then
        echo -e "  ${GREEN}●${NC} Cursor        ${DIM}~/.cursor/hooks.json${NC}"
    else
        echo -e "  ${DIM}○${NC} Cursor        ${DIM}(未安装)${NC}"
    fi

    if [ "$opencode" = "installed" ]; then
        echo -e "  ${GREEN}●${NC} OpenCode      ${DIM}~/.config/opencode/opencode.json${NC}"
    else
        echo -e "  ${DIM}○${NC} OpenCode      ${DIM}(未安装)${NC}"
    fi
}

# 配置 Bark
configure_bark() {
    print_step "3" "5" "配置 Bark 通知"

    if [ -n "$BARK_KEY" ]; then
        log_info "检测到环境变量 BARK_KEY"
        INPUT_BARK_KEY="$BARK_KEY"
    else
        echo ""
        echo -e "${DIM}Bark 是一款 iOS 推送通知 App，可在 App Store 搜索下载${NC}"
        echo -e "${DIM}安装后打开 Bark，复制你的 Key${NC}"
        echo ""
        INPUT_BARK_KEY=$(read_input "请输入你的 Bark Key" "")
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
        log_success "Bark 配置成功"
        echo -e "${DIM}   请查看手机是否收到测试通知${NC}"
    else
        log_warning "Bark 可能配置失败"
        if ! confirm "是否继续安装？" "N"; then
            exit 1
        fi
    fi
}

# 选择要配置的工具（多选界面）
select_tools() {
    print_step "4" "5" "选择要配置的工具"

    # 构建选项列表
    local options=()
    local claude=$(echo "$DETECTION_RESULT" | jq -r '.["claude-code"]')
    local cursor=$(echo "$DETECTION_RESULT" | jq -r '.cursor')
    local opencode=$(echo "$DETECTION_RESULT" | jq -r '.opencode')

    [ "$claude" = "installed" ] && options+=("claude-code:Claude Code - ~/.claude/settings.json")
    [ "$cursor" = "installed" ] && options+=("cursor:Cursor - ~/.cursor/hooks.json")
    [ "$opencode" = "installed" ] && options+=("opencode:OpenCode - ~/.config/opencode/opencode.json")

    if [ ${#options[@]} -eq 0 ]; then
        log_error "没有检测到可配置的 AI 工具"
        exit 1
    fi

    # 使用多选界面
    echo ""
    SELECTED_TOOLS=$(select_multiple "选择要配置的工具 (空格选择，回车确认)" "${options[@]}")

    if [ -z "$SELECTED_TOOLS" ]; then
        log_error "请至少选择一个工具"
        exit 1
    fi

    echo ""
    log_info "已选择: $(echo "$SELECTED_TOOLS" | tr '\n' ', ' | sed 's/,$//')"
}

# 执行安装
do_install() {
    print_step "5" "5" "写入配置"

    # 创建目录
    ensure_dir "$HOME/.cc-notify/bin"
    ensure_dir "$HOME/.cc-notify/lib"

    # 写入用户配置
    write_user_config "$INPUT_BARK_KEY"

    # 安装通知脚本
    install_notify_script

    # 配置选中的工具
    local total=$(echo "$SELECTED_TOOLS" | wc -l | tr -d ' ')
    local current=0

    for tool in $SELECTED_TOOLS; do
        ((current++))
        log_info "配置 $tool..."

        case "$tool" in
            claude-code)
                merge_claude_hooks
                ;;
            cursor)
                write_cursor_hooks
                ;;
            opencode)
                write_opencode_hooks
                ;;
        esac
    done

    echo ""
}

# 显示完成信息
show_complete_info() {
    echo ""
    echo -e "${GREEN}╔──────────────────────────────────────────╗${NC}"
    echo -e "${GREEN}│${NC}  ${BOLD}✅ cc-notify v${VERSION} 安装成功！${NC}                    ${GREEN}│${NC}"
    echo -e "${GREEN}╚──────────────────────────────────────────╝${NC}"
    echo ""
    echo -e "${BOLD}📋 配置文件${NC}"
    echo "   ~/.cc-notify/config.json"
    echo ""
    echo -e "${BOLD}🧪 测试命令${NC}"
    echo -e "   ${CYAN}~/.cc-notify/bin/smart-notify.sh '测试' '安装成功' 'normal'${NC}"
    echo ""
    echo -e "${BOLD}⚠️  授权提示${NC}"
    echo "   首次使用请在 系统设置 → 隐私与安全 → 辅助功能 中授权终端应用"
    echo "   这是前台应用检测功能所需的权限"
    echo ""
    echo -e "${DIM}调试模式: CC_NOTIFY_DEBUG=1 ~/.cc-notify/bin/smart-notify.sh ...${NC}"
    echo ""
}

# ============================================================
# 主流程
# ============================================================

main() {
    print_title
    check_dependencies
    detect_ai_tools
    configure_bark
    select_tools
    do_install
    show_complete_info
}

main
