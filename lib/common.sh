#!/bin/bash
# cc-notify 公共函数库

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 打印标题
print_title() {
    echo ""
    echo -e "${BLUE}🚀 cc-notify 智能通知系统${NC}"
    echo "================================"
}

# 打印步骤
print_step() {
    local step="$1"
    local total="$2"
    local desc="$3"
    echo -e "\n[${step}/${total}] ${desc}..."
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
        log_info "创建目录: $dir"
    fi
}

# 读取用户输入（带默认值）
read_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -p "$prompt: " result
        echo "$result"
    fi
}

# 确认提示
confirm() {
    local prompt="$1"
    local default="${2:-Y}"

    local choice
    if [ "$default" = "Y" ]; then
        read -p "$prompt [Y/n] " choice
        [[ "$choice" =~ ^[Nn]$ ]] && return 1 || return 0
    else
        read -p "$prompt [y/N] " choice
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
