#!/bin/bash
# cc-notify 公共函数库

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_debug() {
    [ "$CC_NOTIFY_DEBUG" = "1" ] && echo -e "${DIM}[DEBUG] $1${NC}"
}

# 打印标题
print_title() {
    echo ""
    echo -e "${BLUE}╔──────────────────────────────────────╗${NC}"
    echo -e "${BLUE}│${NC}  ${BOLD}🚀 cc-notify 智能通知系统${NC}                ${BLUE}│${NC}"
    echo -e "${BLUE}╚──────────────────────────────────────╝${NC}"
    echo ""
}

# 打印步骤
print_step() {
    local step="$1"
    local total="$2"
    local desc="$3"
    echo -e "\n${BOLD}[${step}/${total}]${NC} ${desc}"
}
# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 检查目录是否存在
dir_exists() {
    [ -d "$1" ]
}

# 检查文件是否存在
file_exists() {
    [ -f "$1" ]
}

# 备份文件
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        log_info "已备份: $file"
    fi
}

# 确保目录存在
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        log_debug "创建目录: $dir"
    fi
}

# 读取用户输入（带默认值）
read_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        echo -ne "${prompt} ${DIM}[${default}]${NC}: "
        read result
        echo "${result:-$default}"
    else
        echo -ne "${prompt}: "
        read result
        echo "$result"
    fi
}

# 确认提示
confirm() {
    local prompt="$1"
    local default="${2:-Y}"

    local choice
    if [ "$default" = "Y" ]; then
        echo -ne "${prompt} ${DIM}[Y/n]${NC}: "
        read choice
        [[ "$choice" =~ ^[Nn]$ ]] && return 1 || return 0
    else
        echo -ne "${prompt} ${DIM}[y/N]${NC}: "
        read choice
        [[ "$choice" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# 获取脚本所在目录
get_script_dir() {
    local dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$dir"
}

# 获取项目根目录
get_project_root() {
    local script_dir="$(get_script_dir)"
    echo "$(dirname "$script_dir")"
}

# ============================================================
# 交互式多选界面
# ============================================================

# 检测是否有 fzf
has_fzf() {
    command_exists fzf
}

# 检测是否有 gum
has_gum() {
    command_exists gum
}

# 使用 fzf 进行多选
# 参数：prompt, item1, item2, ...
# 返回：选中的项目（换行分隔）
select_multiple_fzf() {
    local prompt="$1"
    shift
    local items=("$@")

    printf '%s\n' "${items[@]}" | fzf --prompt="$prompt " --multi --height=~40% --reverse --bind "space:toggle"
}

# 使用 gum 进行多选
select_multiple_gum() {
    local prompt="$1"
    shift
    local items=("$@")

    gum choose --prompt="$prompt" --no-limit "${items[@]}"
}

# 纯 bash 多选界面
# 参数：prompt, item1:description1, item2:description2, ...
# 返回：选中的项目名称（换行分隔）
# 纯 bash 多选界面（简化版，更好的兼容性）
# 参数：prompt, item1:description1, item2:description2, ...
# 返回：选中的项目名称（换行分隔）
# 纯 bash 多选界面（数字选择，最大兼容性）
# 参数：prompt, item1:description1, item2:description2, ...
# 返回：选中的项目名称（换行分隔）
select_multiple_bash() {
    local prompt="$1"
    shift
    local items=("$@")

    local total=${#items[@]}

    # 解析项目和描述
    declare -a item_names
    declare -a item_descs
    local i=0
    for item in "${items[@]}"; do
        item_names[$i]="${item%%:*}"
        item_descs[$i]="${item#*:}"
        ((i++))
    done

    # 显示选项
    echo ""
    echo -e "${BOLD}$prompt${NC}"
    echo ""
    
    local j=1
    for name in "${item_names[@]}"; do
        echo -e "  ${CYAN}$j${NC}) $name ${DIM}${item_descs[$((j-1))]}${NC}"
        ((j++))
    done
    
    echo ""
    echo -ne "${DIM}请输入编号（多选用空格分隔，如 1 3）: ${NC}"
    
    local choices
    read choices
    
    # 解析用户输入
    for choice in $choices; do
        # 验证是数字且在范围内
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then
            local idx=$((choice - 1))
            echo "${item_names[$idx]}"
        fi
    done
}




# 智能多选界面（自动选择最佳方式）
# 参数：prompt, item1:description1, item2:description2, ...
# 返回：选中的项目名称（换行分隔）
select_multiple() {
    local prompt="$1"
    shift
    local items=("$@")

    if has_fzf; then
        log_debug "使用 fzf 进行多选"
        # fzf 需要只有名称的列表
        local names=()
        for item in "${items[@]}"; do
            names+=("${item%%:*}")
        done
        select_multiple_fzf "$prompt" "${names[@]}"
    elif has_gum; then
        log_debug "使用 gum 进行多选"
        local names=()
        for item in "${items[@]}"; do
            names+=("${item%%:*}")
        done
        select_multiple_gum "$prompt" "${names[@]}"
    else
        log_debug "使用纯 bash 进行多选"
        select_multiple_bash "$prompt" "${items[@]}"
    fi
}

# 单选界面
# 参数：prompt, item1:description1, item2:description2, ...
# 返回：选中的项目名称
select_single() {
    local prompt="$1"
    shift
    local items=("$@")

    if has_fzf; then
        local names=()
        for item in "${items[@]}"; do
            names+=("${item%%:*}")
        done
        printf '%s\n' "${names[@]}" | fzf --prompt="$prompt " --height=~40% --reverse
    elif has_gum; then
        local names=()
        for item in "${items[@]}"; do
            names+=("${item%%:*}")
        done
        gum choose --prompt="$prompt" "${names[@]}"
    else
        # 纯 bash 单选
        echo -e "\n${BOLD}$prompt${NC}"
        local i=1
        for item in "${items[@]}"; do
            local name="${item%%:*}"
            local desc="${item#*:}"
            echo -e "  ${CYAN}$i${NC}) $name ${DIM}$desc${NC}"
            ((i++))
        done
        echo ""
        local choice
        echo -ne "${DIM}请选择 [1-${#items[@]}]${NC}: "
        read choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#items[@]} ]; then
            local idx=$((choice - 1))
            local selected="${items[$idx]}"
            echo "${selected%%:*}"
        fi
    fi
}

# 进度条
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"

    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    printf "\r${BOLD}%s${NC} [${GREEN}" "$desc"
    printf "%${filled}s" | tr ' ' '█'
    printf "${DIM}"
    printf "%${empty}s" | tr ' ' '░'
    printf "${NC}] %3d%%" "$percent"
}

# 显示完成信息
show_complete() {
    echo ""
    echo -e "${GREEN}╔──────────────────────────────────────╗${NC}"
    echo -e "${GREEN}│${NC}  ${BOLD}✅ cc-notify 安装完成！${NC}                  ${GREEN}│${NC}"
    echo -e "${GREEN}╚──────────────────────────────────────╝${NC}"
}
