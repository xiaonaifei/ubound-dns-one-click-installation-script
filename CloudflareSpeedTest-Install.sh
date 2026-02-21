#!/bin/bash

# ===========================================
# CloudflareSpeedTest 服务器安装脚本
# 功能：下载、解压、设置权限
# 安装路径：/etc/bot/cloudflare
# ===========================================

# 安装配置
INSTALL_DIR="/etc/bot/cloudflare"
VERSION="2.2.4"  # 指定版本号

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 显示标题
echo ""
echo "========================================"
echo "CloudflareSpeedTest 服务器安装脚本"
echo "版本: ${VERSION}"
echo "安装路径: ${INSTALL_DIR}"
echo "========================================"
echo ""

# 1. 检查并创建目录
echo_info "创建安装目录..."
mkdir -p "${INSTALL_DIR}"
if [ $? -ne 0 ]; then
    echo_error "创建目录失败，请检查权限"
    exit 1
fi

# 2. 检测系统架构
echo_info "检测系统架构..."
ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64)
        ARCH="amd64"
        echo_info "检测到系统架构: x86_64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        echo_info "检测到系统架构: ARM64"
        ;;
    armv7l|armv7)
        ARCH="armv7"
        echo_info "检测到系统架构: ARMv7"
        ;;
    *)
        echo_error "不支持的系统架构: ${ARCH}"
        exit 1
        ;;
esac

# 3. 构建下载URL
OS="linux"
DOWNLOAD_URL="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v${VERSION}/CloudflareST_${OS}_${ARCH}.tar.gz"
DOWNLOAD_FILE="/tmp/CloudflareST_${VERSION}_${OS}_${ARCH}.tar.gz"

echo_info "下载地址: ${DOWNLOAD_URL}"

# 4. 下载文件
echo_info "正在下载 CloudflareSpeedTest..."
if command -v wget >/dev/null 2>&1; then
    wget -O "${DOWNLOAD_FILE}" "${DOWNLOAD_URL}"
elif command -v curl >/dev/null 2>&1; then
    curl -L -o "${DOWNLOAD_FILE}" "${DOWNLOAD_URL}"
else
    echo_error "请先安装 wget 或 curl"
    exit 1
fi

if [ $? -ne 0 ] || [ ! -f "${DOWNLOAD_FILE}" ]; then
    echo_error "下载失败"
    exit 1
fi

# 5. 解压文件
echo_info "正在解压文件..."
tar -xzf "${DOWNLOAD_FILE}" -C "${INSTALL_DIR}"
if [ $? -ne 0 ]; then
    echo_error "解压失败"
    exit 1
fi

# 6. 设置权限
echo_info "设置文件权限..."
find "${INSTALL_DIR}" -type f -name "CloudflareST" -exec chmod +x {} \;
find "${INSTALL_DIR}" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
chmod 755 "${INSTALL_DIR}"

# 7. 清理临时文件
echo_info "清理临时文件..."
rm -f "${DOWNLOAD_FILE}"

# 8. 验证安装
echo_info "验证安装..."
if [ -f "${INSTALL_DIR}/CloudflareST" ]; then
    chmod +x "${INSTALL_DIR}/CloudflareST"
    echo_info "可执行文件: ${INSTALL_DIR}/CloudflareST"
else
    # 尝试查找其他可能的可执行文件
    EXECUTABLE=$(find "${INSTALL_DIR}" -type f -executable -name "*Cloudflare*" | head -1)
    if [ -n "${EXECUTABLE}" ]; then
        echo_info "可执行文件: ${EXECUTABLE}"
    else
        echo_warn "未找到可执行文件，请检查解压结果"
    fi
fi

# 9. 显示结果
echo ""
echo "========================================"
echo "安装完成!"
echo "========================================"
echo "安装路径: ${INSTALL_DIR}"
echo "版本: ${VERSION}"
echo "系统: ${OS}-${ARCH}"
echo ""
echo "使用命令:"
echo "  cd ${INSTALL_DIR}"
echo "  ./CloudflareST -h"
echo ""
echo "文件列表:"
ls -lh "${INSTALL_DIR}/"
echo "========================================"