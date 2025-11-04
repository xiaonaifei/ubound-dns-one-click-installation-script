#!/bin/bash

# 修复无效软件源并安装最新BBR内核脚本
# 适用于 Ubuntu/Debian 系统

set -e

# 颜色输出设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 打印状态信息
info() {
    echo -e "${GREEN}[信息] $*${NC}"
}

warn() {
    echo -e "${YELLOW}[警告] $*${NC}"
}

error() {
    echo -e "${RED}[错误] $*${NC}" >&2
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 修复无效的rspamd软件源
fix_rspamd_repo() {
    info "检查并修复rspamd软件源..."
    
    # 查找包含rspamd.com的源文件
    local rspamd_files=$(grep -l "rspamd.com" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true)
    
    if [ -n "$rspamd_files" ]; then
        warn "发现rspamd软件源，正在禁用..."
        for file in $rspamd_files; do
            # 备份原文件
            cp "$file" "${file}.bak"
            # 注释掉rspamd源
            sed -i '/rspamd.com/s/^/#/' "$file"
            info "已禁用文件 $file 中的rspamd源"
        done
    else
        info "未找到rspamd软件源"
    fi
}

# 为Ubuntu/Debian安装最新内核
install_ubuntu_kernel() {
    info "为Ubuntu/Debian安装最新内核..."
    
    # 先更新软件包列表
    apt-get update
    
    # 安装必要工具
    apt-get install -y software-properties-common
    
    # 添加官方内核PPA
    add-apt-repository -y ppa:canonical-kernel-team/ppa
    
    # 再次更新
    apt-get update
    
    # 安装最新内核
    apt-get install -y --install-recommends linux-generic-hwe-$(lsb_release -rs)
}

# 配置BBR
configure_bbr() {
    info "配置BBR..."
    
    # 检查并添加sysctl配置
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    
    # 应用配置
    sysctl -p
}

# 设置GRUB启动项
set_grub() {
    info "更新GRUB配置..."
    
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    fi
    
    # 设置最新内核为默认启动项
    if command -v grub-set-default >/dev/null 2>&1; then
        grub-set-default 0
    fi
}

# 验证BBR状态
verify_bbr() {
    info "验证BBR状态..."
    
    # 检查当前拥塞控制算法
    CC_ALGORITHM=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [ "$CC_ALGORITHM" = "bbr" ]; then
        info "BBR 已成功启用"
    else
        warn "BBR 未启用，当前算法: $CC_ALGORITHM"
    fi
    
    # 检查内核版本
    KERNEL_VERSION=$(uname -r)
    info "当前内核版本: $KERNEL_VERSION"
}

# 主函数
main() {
    info "开始修复软件源并安装最新BBR内核..."
    check_root
    
    # 检查系统是否为Ubuntu/Debian
    if ! grep -q "Ubuntu\|Debian" /etc/issue; then
        error "此脚本仅适用于Ubuntu/Debian系统"
        exit 1
    fi
    
    fix_rspamd_repo
    install_ubuntu_kernel
    set_grub
    configure_bbr
    
    info "安装完成！需要重启系统以使更改生效。"
    read -p "是否立即重启系统? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        warn "系统即将重启..."
        sleep 3
        reboot
    else
        info "请稍后手动重启系统以完成安装"
    fi
}

# 执行主函数
main "$@"