#!/bin/bash

# ===========================================
# 服务器开源中文字体安装脚本
# 专注安装开源免费字体
# 使用方法: sudo bash open-font-installer.sh
# ===========================================

set -e  # 遇到错误立即退出

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 字体安装目录
FONT_DIR="/usr/share/fonts/chinese-opensource"

# 开源字体下载源
OPEN_FONTS=(
    # 思源黑体
    "SourceHanSans|思源黑体|https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSansSC.zip|思源黑体"
    "SourceHanSansHK|思源黑体香港|https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSansHK.zip|思源黑体香港"
    "SourceHanSansTW|思源黑体台湾|https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSansTW.zip|思源黑体台湾"
    
    # 思源宋体
    "SourceHanSerif|思源宋体|https://github.com/adobe-fonts/source-han-serif/releases/download/2.001R/SourceHanSerifSC.zip|思源宋体"
    "SourceHanSerifHK|思源宋体香港|https://github.com/adobe-fonts/source-han-serif/releases/download/2.001R/SourceHanSerifHK.zip|思源宋体香港"
    "SourceHanSerifTW|思源宋体台湾|https://github.com/adobe-fonts/source-han-serif/releases/download/2.001R/SourceHanSerifTW.zip|思源宋体台湾"
    
    # Noto Sans CJK (Google开源字体)
    "NotoSansCJK|Noto Sans CJK|https://github.com/googlefonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK.ttc.zip|Noto Sans CJK"
    
    # LXGW WenKai (霞鹜文楷)
    "LXGWWenKai|霞鹜文楷|https://github.com/lxgw/LxgwWenKai/releases/download/v1.300/LXGWWenKai-Regular.ttf|霞鹜文楷常规体"
    "LXGWWenKaiMono|霞鹜文楷等宽|https://github.com/lxgw/LxgwWenKai/releases/download/v1.300/LXGWWenKaiMono-Regular.ttf|霞鹜文楷等宽体"
    
    # 文泉驿字体
    "WenQuanYi|文泉驿微米黑|http://downloads.sourceforge.net/project/wqy/wqy-microhei/0.2.0-beta/wqy-microhei-0.2.0-beta.tar.gz|文泉驿微米黑"
    
    # 得意黑 (开源美术字体)
    "SmileySans|得意黑|https://github.com/atelier-anchor/smiley-sans/releases/download/v1.1.1/SmileySans-Oblique.ttf.7z|得意黑倾斜体"
)

# 备用镜像源（中国大陆优化）
MIRRORS=(
    "https://ghproxy.com/"  # GitHub代理
    "https://mirror.ghproxy.com/"
    "https://kgithub.com/"  # GitHub镜像
    ""  # 原始地址
)

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查权限
check_permission() {
    if [[ $EUID -ne 0 ]]; then
        log_warning "建议使用 root 权限运行此脚本"
        read -p "是否继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 检查系统包管理器
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# 安装系统依赖
install_dependencies() {
    local pkg_manager=$(detect_package_manager)
    
    log_info "安装系统依赖..."
    
    case $pkg_manager in
        apt)
            apt-get update
            apt-get install -y wget curl unzip fontconfig p7zip-full
            ;;
        yum)
            yum install -y wget curl unzip fontconfig p7zip
            ;;
        dnf)
            dnf install -y wget curl unzip fontconfig p7zip
            ;;
        pacman)
            pacman -Sy --noconfirm wget curl unzip fontconfig p7zip
            ;;
        zypper)
            zypper install -y wget curl unzip fontconfig p7zip
            ;;
        *)
            log_warning "无法识别的包管理器，请手动安装: wget, curl, unzip, fontconfig, p7zip"
            return 1
            ;;
    esac
    
    log_success "系统依赖安装完成"
}

# 创建字体目录
create_font_dir() {
    log_info "创建字体目录: $FONT_DIR"
    
    if [[ ! -d "$FONT_DIR" ]]; then
        mkdir -p "$FONT_DIR"
        chmod 755 "$FONT_DIR"
        log_success "字体目录创建完成"
    else
        log_info "字体目录已存在"
    fi
}

# 下载工具函数
download_with_fallback() {
    local url=$1
    local output=$2
    local filename=$(basename "$output")
    local downloaded=false
    
    log_info "下载: $filename"
    
    # 尝试各个镜像源
    for mirror in "${MIRRORS[@]}"; do
        local full_url="${mirror}${url}"
        if [[ -z "$mirror" ]]; then
            full_url="$url"  # 原始地址
        fi
        
        log_info "尝试: $(echo "$full_url" | sed 's|https://||' | cut -c1-50)..."
        
        if wget --timeout=30 --tries=2 -q "$full_url" -O "$output"; then
            downloaded=true
            log_success "下载成功"
            break
        else
            log_warning "下载失败，尝试下一个镜像..."
            rm -f "$output" 2>/dev/null || true
        fi
    done
    
    if [ "$downloaded" = false ]; then
        log_error "所有镜像源都失败了"
        return 1
    fi
    
    return 0
}

# 解压字体文件
extract_font_file() {
    local file=$1
    local ext="${file##*.}"
    
    case $ext in
        zip|ZIP)
            unzip -q -o "$file" -d "$FONT_DIR"
            ;;
        gz|GZ|tgz|TGZ)
            tar -xzf "$file" -C "$FONT_DIR" --strip-components=1 2>/dev/null || \
            tar -xzf "$file" -C "$FONT_DIR"
            ;;
        7z|7Z)
            7z x -y "$file" -o"$FONT_DIR" > /dev/null
            ;;
        ttf|TTF|otf|OTF|ttc|TTC)
            cp "$file" "$FONT_DIR/"
            ;;
        *)
            log_error "不支持的文件格式: $ext"
            return 1
            ;;
    esac
    
    # 清理压缩包
    rm -f "$file"
}

# 安装单个开源字体
install_open_font() {
    local font_id=$1
    local font_name=$2
    local font_url=$3
    local font_desc=$4
    
    log_info "安装开源字体: $font_desc"
    
    # 临时文件
    local temp_file="/tmp/font_${font_id}_$(date +%s).${font_url##*.}"
    
    # 下载字体
    if ! download_with_fallback "$font_url" "$temp_file"; then
        log_warning "跳过字体: $font_desc"
        return 1
    fi
    
    # 解压并安装
    if extract_font_file "$temp_file"; then
        log_success "字体安装成功: $font_desc"
        return 0
    else
        log_error "字体解压失败: $font_desc"
        return 1
    fi
}

# 通过包管理器安装开源字体
install_fonts_via_package_manager() {
    local pkg_manager=$(detect_package_manager)
    
    log_info "通过包管理器安装开源中文字体..."
    
    case $pkg_manager in
        apt)
            apt-get install -y \
                fonts-noto-cjk \
                fonts-wqy-microhei \
                fonts-wqy-zenhei \
                ttf-wqy-zenhei
            ;;
        yum)
            yum install -y \
                google-noto-sans-cjk-fonts \
                wqy-microhei-fonts \
                wqy-zenhei-fonts
            ;;
        dnf)
            dnf install -y \
                google-noto-sans-cjk-fonts \
                wqy-microhei-fonts \
                wqy-zenhei-fonts
            ;;
        pacman)
            pacman -S --noconfirm \
                noto-fonts-cjk \
                wqy-microhei \
                ttf-wqy-zenhei
            ;;
        zypper)
            zypper install -y \
                google-noto-sans-cjk-fonts \
                wqy-microhei-fonts
            ;;
        *)
            log_warning "无法通过包管理器安装字体"
            return 1
            ;;
    esac
    
    log_success "包管理器字体安装完成"
}

# 更新字体缓存
update_font_cache() {
    log_info "更新字体缓存..."
    
    if ! command -v fc-cache &> /dev/null; then
        log_warning "fc-cache 命令不存在，跳过缓存更新"
        return
    fi
    
    # 更新字体目录缓存
    if [[ -d "$FONT_DIR" ]]; then
        fc-cache -f -v "$FONT_DIR" 2>/dev/null || true
        log_info "已更新目录: $FONT_DIR"
    fi
    
    # 更新系统字体缓存
    fc-cache -f -v 2>/dev/null || true
    
    log_success "字体缓存更新完成"
}

# 列出已安装的开源字体
list_installed_fonts() {
    log_info "已安装的开源中文字体:"
    echo "========================================"
    
    if command -v fc-list &> /dev/null; then
        # 列出主要开源中文字体
        local open_font_patterns=(
            "Source Han"
            "Noto"
            "WenQuanYi"
            "WQY"
            "LXGW"
            "Smiley"
            "文泉驿"
            "霞鹜"
            "得意黑"
        )
        
        for pattern in "${open_font_patterns[@]}"; do
            fc-list : family 2>/dev/null | grep -i "$pattern" | sort | uniq
        done | sort | uniq
    else
        # 直接从字体目录查看
        find "$FONT_DIR" -name "*.ttf" -o -name "*.otf" -o -name "*.ttc" 2>/dev/null | \
            head -20 | xargs -I {} basename {} | sort
    fi
    
    echo "========================================"
}

# 创建优化的字体配置
create_font_config() {
    log_info "创建开源字体优化配置..."
    
    local conf_dir="/etc/fonts/conf.d"
    local conf_file="$conf_dir/65-chinese-opensource.conf"
    
    if [[ ! -d "$conf_dir" ]]; then
        mkdir -p "$conf_dir"
    fi
    
    cat > "$conf_file" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <!-- 开源中文字体目录 -->
    <dir>/usr/share/fonts/chinese-opensource</dir>
    
    <!-- 字体替换规则：优先使用开源字体 -->
    <alias>
        <family>sans-serif</family>
        <prefer>
            <!-- 思源黑体系列 -->
            <family>Source Han Sans SC</family>
            <family>Source Han Sans TC</family>
            <family>Source Han Sans HC</family>
            <!-- Noto系列 -->
            <family>Noto Sans CJK SC</family>
            <family>Noto Sans CJK TC</family>
            <family>Noto Sans CJK HK</family>
            <!-- 文泉驿系列 -->
            <family>WenQuanYi Micro Hei</family>
            <family>WenQuanYi Zen Hei</family>
            <!-- 霞鹜文楷 -->
            <family>LXGW WenKai</family>
            <!-- 系统回退字体 -->
            <family>DejaVu Sans</family>
            <family>Liberation Sans</family>
            <family>Arial</family>
        </prefer>
    </alias>
    
    <alias>
        <family>serif</family>
        <prefer>
            <!-- 思源宋体系列 -->
            <family>Source Han Serif SC</family>
            <family>Source Han Serif TC</family>
            <family>Source Han Serif HC</family>
            <!-- Noto系列 -->
            <family>Noto Serif CJK SC</family>
            <family>Noto Serif CJK TC</family>
            <family>Noto Serif CJK HK</family>
            <!-- 系统回退字体 -->
            <family>DejaVu Serif</family>
            <family>Liberation Serif</family>
            <family>Times New Roman</family>
        </prefer>
    </alias>
    
    <alias>
        <family>monospace</family>
        <prefer>
            <!-- 等宽字体 -->
            <family>LXGW WenKai Mono</family>
            <family>Noto Sans Mono CJK SC</family>
            <!-- 系统回退等宽字体 -->
            <family>DejaVu Sans Mono</family>
            <family>Liberation Mono</family>
            <family>Courier New</family>
        </prefer>
    </alias>
    
    <!-- 为常见字体名称设置别名 -->
    <match target="pattern">
        <test qual="any" name="family">
            <string>SimSun</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
            <string>Source Han Serif SC</string>
        </edit>
    </match>
    
    <match target="pattern">
        <test qual="any" name="family">
            <string>SimHei</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
            <string>Source Han Sans SC</string>
        </edit>
    </match>
    
    <match target="pattern">
        <test qual="any" name="family">
            <string>Microsoft YaHei</string>
        </test>
        <edit name="family" mode="assign" binding="strong">
            <string>Source Han Sans SC</string>
        </edit>
    </match>
    
    <!-- 字体渲染优化 -->
    <match target="font">
        <edit name="antialias" mode="assign">
            <bool>true</bool>
        </edit>
        <edit name="hinting" mode="assign">
            <bool>true</bool>
        </edit>
        <edit name="hintstyle" mode="assign">
            <const>hintslight</const>
        </edit>
        <edit name="rgba" mode="assign">
            <const>rgb</const>
        </edit>
        <edit name="lcdfilter" mode="assign">
            <const>lcddefault</const>
        </edit>
    </match>
</fontconfig>
EOF
    
    chmod 644 "$conf_file"
    log_success "字体配置文件创建完成: $conf_file"
}

# 显示开源字体列表
show_open_font_list() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}    开源中文字体列表${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    local i=1
    for font_entry in "${OPEN_FONTS[@]}"; do
        IFS='|' read -r id name url desc <<< "$font_entry"
        echo -e "${GREEN}$i.${NC} $desc"
        ((i++))
    done
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# 安装所有开源字体
install_all_open_fonts() {
    log_info "开始安装所有开源中文字体..."
    
    local installed_count=0
    local total_count=${#OPEN_FONTS[@]}
    
    for font_entry in "${OPEN_FONTS[@]}"; do
        IFS='|' read -r id name url desc <<< "$font_entry"
        
        if install_open_font "$id" "$name" "$url" "$desc"; then
            ((installed_count++))
        fi
        
        echo ""
    done
    
    log_success "安装完成: $installed_count/$total_count 个字体"
}

# 安装选择的字体
install_selected_fonts() {
    echo "请选择要安装的字体（多个用逗号分隔，或输入 all 安装全部）:"
    read -p "选择: " choices
    
    if [[ "$choices" == "all" ]]; then
        install_all_open_fonts
        return
    fi
    
    IFS=',' read -ra selected <<< "$choices"
    local installed_count=0
    
    for choice in "${selected[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        if [[ $choice -ge 1 && $choice -le ${#OPEN_FONTS[@]} ]]; then
            local idx=$((choice-1))
            local font_entry="${OPEN_FONTS[$idx]}"
            IFS='|' read -r id name url desc <<< "$font_entry"
            
            if install_open_font "$id" "$name" "$url" "$desc"; then
                ((installed_count++))
            fi
        else
            log_warning "无效的选择: $choice"
        fi
    done
    
    log_success "安装完成: $installed_count 个字体"
}

# 显示主菜单
show_menu() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}    服务器开源中文字体安装脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "1. 查看开源字体列表"
    echo "2. 安装所有开源字体"
    echo "3. 选择安装特定字体"
    echo "4. 通过系统包管理器安装字体"
    echo "5. 仅更新字体缓存和配置"
    echo "6. 查看已安装字体"
    echo "0. 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# 主函数
main() {
    clear
    check_permission
    
    while true; do
        show_menu
        read -p "请选择操作 (0-6): " choice
        
        case $choice in
            1)
                show_open_font_list
                ;;
            2)
                install_dependencies
                create_font_dir
                install_all_open_fonts
                create_font_config
                update_font_cache
                list_installed_fonts
                ;;
            3)
                install_dependencies
                create_font_dir
                show_open_font_list
                install_selected_fonts
                create_font_config
                update_font_cache
                list_installed_fonts
                ;;
            4)
                install_dependencies
                install_fonts_via_package_manager
                update_font_cache
                list_installed_fonts
                ;;
            5)
                create_font_dir
                create_font_config
                update_font_cache
                list_installed_fonts
                ;;
            6)
                list_installed_fonts
                ;;
            0)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效的选择"
                ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
        clear
    done
}

# 执行主函数
main "$@"