#!/bin/bash

# Unbound with Yeti DNS Root Server 一键安装脚本 (纯递归模式)
# 配置目录: /usr/local/etc/unbound/
# 根提示文件: /usr/local/etc/unbound/root/named.cache

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 变量定义
UNBOUND_PORT="53"
UNBOUND_CONFIG_DIR="/usr/local/etc/unbound"
UNBOUND_ROOT_HINTS="$UNBOUND_CONFIG_DIR/root/named.cache"

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用root权限运行此脚本${NC}"
    exit 1
fi

# 显示标题
echo -e "${BLUE}"
echo "================================================"
echo "    Unbound DNS 解析器安装脚本 (Yeti DNS)"
echo "================================================"
echo -e "${NC}"

# 用户输入函数
get_user_input() {
    echo -e "${YELLOW}配置选项${NC}"
    echo "--------------------------------"
    
    # 获取端口号
    while true; do
        read -p "请输入Unbound监听端口 [默认: 53]: " input_port
        if [ -z "$input_port" ]; then
            UNBOUND_PORT="53"
            break
        elif [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
            UNBOUND_PORT="$input_port"
            break
        else
            echo -e "${RED}错误: 端口号必须是1-65535之间的数字${NC}"
        fi
    done
    
    echo -e "${GREEN}✓ Unbound将监听端口: $UNBOUND_PORT${NC}"
    echo ""
}

# 设置临时DNS确保网络连接
setup_temporary_dns() {
    echo -e "${YELLOW}设置临时DNS服务器确保网络连接...${NC}"
    
    # 备份当前DNS配置
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d%H%M%S)
        echo -e "${GREEN}✓ 已备份当前DNS配置${NC}"
    fi
    
    # 设置临时DNS
    cat > /etc/resolv.conf << 'EOF'
# Temporary DNS configuration for Unbound installation
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 114.114.114.114
options timeout:2 attempts:3 rotate
EOF
    
    echo -e "${GREEN}✓ 临时DNS设置完成${NC}"
    echo ""
}

# 恢复原始DNS配置
restore_original_dns() {
    if ls /etc/resolv.conf.backup.* 1> /dev/null 2>&1; then
        echo -e "${YELLOW}恢复原始DNS配置...${NC}"
        cp /etc/resolv.conf.backup.* /etc/resolv.conf
        echo -e "${GREEN}✓ DNS配置已恢复${NC}"
    fi
}

# 检查并处理端口占用
check_port_usage() {
    echo -e "${YELLOW}检查端口 $UNBOUND_PORT 占用情况...${NC}"
    
    # 检查TCP和UDP端口
    local tcp_listeners=$(ss -tulpn | grep ":$UNBOUND_PORT " | grep LISTEN || true)
    local udp_listeners=$(ss -tulpn | grep ":$UNBOUND_PORT " | grep UDP || true)
    
    if [ -n "$tcp_listeners" ] || [ -n "$udp_listeners" ]; then
        echo -e "${RED}发现端口 $UNBOUND_PORT 被占用:${NC}"
        
        # 显示占用进程
        if [ -n "$tcp_listeners" ]; then
            echo -e "${YELLOW}TCP监听:${NC}"
            echo "$tcp_listeners"
        fi
        if [ -n "$udp_listeners" ]; then
            echo -e "${YELLOW}UDP监听:${NC}"
            echo "$udp_listeners"
        fi
        
        # 获取占用端口的服务
        local services=$(ss -tulpn | grep ":$UNBOUND_PORT " | awk '{print $7}' | cut -d'"' -f2 | sort -u)
        
        echo ""
        echo -e "${YELLOW}请选择处理方式:${NC}"
        echo "1) 永久停用占用端口的服务"
        echo "2) 卸载占用端口的软件"
        echo "3) 更改Unbound监听端口"
        echo "4) 退出安装"
        
        while true; do
            read -p "请选择 [1-4]: " choice
            case $choice in
                1)
                    disable_services "$services"
                    break
                    ;;
                2)
                    uninstall_services "$services"
                    break
                    ;;
                3)
                    change_unbound_port
                    break
                    ;;
                4)
                    echo -e "${YELLOW}安装已取消${NC}"
                    restore_original_dns
                    exit 0
                    ;;
                *)
                    echo -e "${RED}无效选择，请重新输入${NC}"
                    ;;
            esac
        done
    else
        echo -e "${GREEN}✓ 端口 $UNBOUND_PORT 未被占用${NC}"
        echo ""
    fi
}

# 永久停用服务
disable_services() {
    local services="$1"
    echo -e "${YELLOW}永久停用服务...${NC}"
    
    for service in $services; do
        if [ -n "$service" ] && [ "$service" != "-" ]; then
            echo -e "${YELLOW}处理服务: $service${NC}"
            
            # 停止服务
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                systemctl stop "$service"
                echo -e "${GREEN}✓ 已停止服务: $service${NC}"
            fi
            
            # 禁用服务（永久暂停）
            if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                systemctl disable "$service"
                echo -e "${GREEN}✓ 已禁用服务: $service${NC}"
            fi
            
            # 对于非systemd服务，使用pkill
            pkill -f "$service" 2>/dev/null || true
        fi
    done
    
    # 强制杀死占用端口的进程
    local pids=$(lsof -ti:$UNBOUND_PORT 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo -e "${YELLOW}强制结束进程: $pids${NC}"
        kill -9 $pids 2>/dev/null || true
    fi
    
    # 验证端口是否释放
    sleep 2
    if ss -tulpn | grep -q ":$UNBOUND_PORT "; then
        echo -e "${RED}错误: 无法释放端口 $UNBOUND_PORT${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ 端口 $UNBOUND_PORT 已释放${NC}"
        echo ""
    fi
}

# 卸载服务
uninstall_services() {
    local services="$1"
    echo -e "${YELLOW}卸载软件包...${NC}"
    
    for service in $services; do
        if [ -n "$service" ] && [ "$service" != "-" ]; then
            echo -e "${YELLOW}处理服务对应的软件包: $service${NC}"
            
            # 停止服务
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                systemctl stop "$service"
            fi
            
            # 根据系统类型卸载软件包
            if [ -f /etc/redhat-release ]; then
                # CentOS/RHEL - 尝试找出包名并卸载
                local pkg_name=$(rpm -qf "$(which $service 2>/dev/null || echo $service)" 2>/dev/null || echo "")
                if [ -n "$pkg_name" ]; then
                    yum remove -y "$pkg_name"
                    echo -e "${GREEN}✓ 已卸载: $pkg_name${NC}"
                else
                    echo -e "${YELLOW}⚠ 无法确定 $service 的软件包名称${NC}"
                fi
            elif [ -f /etc/debian_version ]; then
                # Debian/Ubuntu - 尝试找出包名并卸载
                local pkg_name=$(dpkg -S "$(which $service 2>/dev/null || echo $service)" 2>/dev/null | cut -d: -f1 || echo "")
                if [ -n "$pkg_name" ]; then
                    apt remove -y "$pkg_name"
                    echo -e "${GREEN}✓ 已卸载: $pkg_name${NC}"
                else
                    echo -e "${YELLOW}⚠ 无法确定 $service 的软件包名称${NC}"
                fi
            fi
            
            # 强制杀死相关进程
            pkill -f "$service" 2>/dev/null || true
        fi
    done
    
    # 验证端口是否释放
    sleep 2
    if ss -tulpn | grep -q ":$UNBOUND_PORT "; then
        echo -e "${RED}错误: 无法释放端口 $UNBOUND_PORT${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ 端口 $UNBOUND_PORT 已释放${NC}"
        echo ""
    fi
}

# 更改Unbound端口
change_unbound_port() {
    echo ""
    echo -e "${YELLOW}更改Unbound监听端口${NC}"
    while true; do
        read -p "请输入新的端口号: " new_port
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
            # 检查新端口是否也被占用
            if ss -tulpn | grep -q ":$new_port "; then
                echo -e "${RED}端口 $new_port 也被占用，请选择其他端口${NC}"
            else
                UNBOUND_PORT="$new_port"
                echo -e "${GREEN}✓ Unbound将使用端口: $UNBOUND_PORT${NC}"
                echo -e "${YELLOW}注意: 使用非53端口时，系统DNS需要手动配置${NC}"
                break
            fi
        else
            echo -e "${RED}错误: 端口号必须是1-65535之间的数字${NC}"
        fi
    done
    echo ""
}

# 安装依赖和Unbound
install_unbound() {
    # 检测系统类型并安装依赖
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        echo -e "${YELLOW}检测到CentOS/RHEL系统，安装依赖...${NC}"
        yum update -y
        yum install -y wget gcc openssl-devel expat-devel make
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        echo -e "${YELLOW}检测到Debian/Ubuntu系统，安装依赖...${NC}"
        apt update
        apt install -y wget gcc libssl-dev libexpat1-dev make
    else
        echo -e "${RED}不支持的操作系统${NC}"
        restore_original_dns
        exit 1
    fi

    # 下载并编译安装Unbound
    echo -e "${YELLOW}下载并编译安装Unbound...${NC}"
    cd /tmp
    if [ ! -f unbound-latest.tar.gz ]; then
        wget https://www.unbound.net/downloads/unbound-latest.tar.gz
    fi
    tar xzf unbound-latest.tar.gz
    cd unbound-*

    ./configure --prefix=/usr/local --sysconfdir=$UNBOUND_CONFIG_DIR --with-pidfile=/var/run/unbound.pid
    make
    make install

    # 创建unbound用户和组（如果不存在）
    if ! id "unbound" &>/dev/null; then
        echo -e "${YELLOW}创建unbound用户和组...${NC}"
        groupadd unbound
        useradd -r -g unbound -s /bin/false unbound
    fi

    # 创建必要的目录
    echo -e "${YELLOW}创建配置目录...${NC}"
    mkdir -p $UNBOUND_CONFIG_DIR/root
    mkdir -p /var/log/unbound
    mkdir -p /var/run/unbound

    # 下载Yeti根提示文件
    echo -e "${YELLOW}下载Yeti根提示文件...${NC}"
    wget -O $UNBOUND_ROOT_HINTS https://raw.githubusercontent.com/BII-Lab/Yeti-Project/master/domain/named.cache

    # 验证下载的文件
    if [ ! -s $UNBOUND_ROOT_HINTS ]; then
        echo -e "${RED}错误: 根提示文件下载失败或为空${NC}"
        echo -e "${YELLOW}尝试备用下载源...${NC}"
        wget -O $UNBOUND_ROOT_HINTS https://yeti-dns.org/root.hints
    fi

    # 设置目录和文件权限
    chown -R unbound:unbound $UNBOUND_CONFIG_DIR/
    chown -R unbound:unbound /var/log/unbound/
    chown -R unbound:unbound /var/run/unbound/
}

# 配置Unbound
configure_unbound() {
    # 创建Unbound配置文件
    echo -e "${YELLOW}创建Unbound配置文件...${NC}"
    cat > $UNBOUND_CONFIG_DIR/unbound.conf << EOF
server:
    # 基本配置
    verbosity: 1
    interface: 0.0.0.0
    interface: ::0
    port: $UNBOUND_PORT
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes
    
    # 访问控制
    access-control: 0.0.0.0/0 allow
    access-control: ::0/0 allow
    
    # 递归解析配置
    do-not-query-localhost: no
    
    # Yeti DNS根服务器配置（纯递归模式）
    root-hints: "$UNBOUND_ROOT_HINTS"
    
    # 不使用转发，纯递归模式
    # 不配置任何forward-zone
    
    # 缓存设置
    cache-min-ttl: 3600
    cache-max-ttl: 86400
    prefetch: yes
    prefetch-key: yes
    
    # 性能优化
    num-threads: 2
    msg-cache-slabs: 4
    rrset-cache-slabs: 4
    infra-cache-slabs: 4
    key-cache-slabs: 4
    
    # 基础设施缓存
    infra-host-ttl: 900
    infra-cache-numhosts: 10000
    
    # 安全设置
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: yes
    unwanted-reply-threshold: 10000000
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10
    
    # DNSSEC配置
    auto-trust-anchor-file: "$UNBOUND_CONFIG_DIR/root.key"
    val-clean-additional: yes
    
    # 积极NSEC缓存
    aggressive-nsec: yes

# 远程控制配置（用于缓存管理）
remote-control:
    control-enable: yes
    control-interface: 127.0.0.1
    control-port: 8953
EOF

    # 初始化根信任锚
    echo -e "${YELLOW}初始化DNSSEC根信任锚...${NC}"
    if [ -f /usr/local/sbin/unbound-anchor ]; then
        /usr/local/sbin/unbound-anchor -a "$UNBOUND_CONFIG_DIR/root.key" -r "$UNBOUND_ROOT_HINTS" || true
    fi

    # 设置权限
    chown unbound:unbound $UNBOUND_ROOT_HINTS
    chown unbound:unbound $UNBOUND_CONFIG_DIR/unbound.conf
    if [ -f "$UNBOUND_CONFIG_DIR/root.key" ]; then
        chown unbound:unbound "$UNBOUND_CONFIG_DIR/root.key"
    fi

    # 检查配置文件语法
    echo -e "${YELLOW}检查配置文件语法...${NC}"
    if /usr/local/sbin/unbound-checkconf $UNBOUND_CONFIG_DIR/unbound.conf; then
        echo -e "${GREEN}✓ 配置文件语法正确${NC}"
    else
        echo -e "${RED}✗ 配置文件语法错误${NC}"
        restore_original_dns
        exit 1
    fi
}

# 创建systemd服务
setup_systemd_service() {
    # 创建systemd服务文件
    echo -e "${YELLOW}创建systemd服务...${NC}"
    cat > /etc/systemd/system/unbound.service << EOF
[Unit]
Description=Unbound DNS resolver
After=network.target

[Service]
User=unbound
Group=unbound
Type=forking
PIDFile=/var/run/unbound.pid
ExecStart=/usr/local/sbin/unbound -d -c $UNBOUND_CONFIG_DIR/unbound.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

# 配置防火墙
setup_firewall() {
    echo -e "${YELLOW}配置防火墙...${NC}"
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$UNBOUND_PORT/udp
        firewall-cmd --permanent --add-port=$UNBOUND_PORT/tcp
        firewall-cmd --reload
        echo -e "${GREEN}✓ 防火墙已配置，开放端口 $UNBOUND_PORT${NC}"
    elif command -v ufw >/dev/null 2>&1; then
        ufw allow $UNBOUND_PORT
        echo -e "${GREEN}✓ 防火墙已配置，开放端口 $UNBOUND_PORT${NC}"
    else
        echo -e "${YELLOW}⚠ 未检测到防火墙管理工具，请手动开放端口 $UNBOUND_PORT${NC}"
    fi
    echo ""
}

# 启动和测试服务
start_and_test_service() {
    # 启动服务
    echo -e "${YELLOW}启动Unbound服务...${NC}"
    systemctl daemon-reload
    systemctl enable unbound
    systemctl start unbound

    # 等待服务启动
    sleep 5

    # 检查服务状态和端口绑定
    echo -e "${YELLOW}检查服务状态...${NC}"
    if systemctl is-active --quiet unbound; then
        echo -e "${GREEN}✓ Unbound服务运行正常${NC}"
        
        # 检查端口绑定
        if ss -tulpn | grep -q 'unbound' && ss -tulpn | grep -q ":$UNBOUND_PORT "; then
            echo -e "${GREEN}✓ Unbound成功绑定端口 $UNBOUND_PORT${NC}"
        else
            echo -e "${RED}✗ Unbound未正确绑定端口 $UNBOUND_PORT${NC}"
            restore_original_dns
            exit 1
        fi
        
        # 测试DNS解析
        echo -e "${YELLOW}测试DNS解析...${NC}"
        if /usr/local/sbin/unbound-host -C $UNBOUND_CONFIG_DIR/unbound.conf -v yeti-dns.org >/dev/null 2>&1; then
            echo -e "${GREEN}✓ DNS解析测试成功${NC}"
        else
            echo -e "${YELLOW}⚠ 首次解析可能较慢，请稍后测试${NC}"
        fi
    else
        echo -e "${RED}✗ Unbound服务启动失败${NC}"
        journalctl -u unbound --no-pager -l
        restore_original_dns
        exit 1
    fi
}

# 创建工具脚本
create_utility_scripts() {
    # 创建更新脚本
    cat > /usr/local/bin/update-yeti-root.sh << 'EOF'
#!/bin/bash
# Yeti根提示文件更新脚本

echo "更新Yeti DNS根提示文件..."
CONFIG_DIR="/usr/local/etc/unbound"
ROOT_HINTS="$CONFIG_DIR/root/named.cache"

wget -O $ROOT_HINTS.tmp https://raw.githubusercontent.com/BII-Lab/Yeti-Project/master/domain/named.cache

if [ $? -eq 0 ] && [ -s $ROOT_HINTS.tmp ]; then
    mv $ROOT_HINTS.tmp $ROOT_HINTS
    chown unbound:unbound $ROOT_HINTS
    systemctl reload unbound
    echo "✓ Yeti根提示文件更新成功"
else
    echo "✗ 更新失败"
    rm -f $ROOT_HINTS.tmp
fi
EOF

    chmod +x /usr/local/bin/update-yeti-root.sh

    # 创建端口监控脚本
    cat > /usr/local/bin/check-dns-port.sh << EOF
#!/bin/bash
# DNS端口监控脚本

echo "=== DNS端口占用检查 ==="
echo "当前 $UNBOUND_PORT 端口监听情况:"
ss -tulpn | grep ":$UNBOUND_PORT " | while read line; do
    echo "  \$line"
done

echo -e "\n=== 系统DNS服务状态 ==="
systemctl list-unit-files | grep -E '(dns|resolv|bind|named)' | while read service status; do
    if [ "\$status" = "enabled" ] || [ "\$status" = "disabled" ]; then
        active_status=\$(systemctl is-active \$service 2>/dev/null || echo "unknown")
        echo "  \$service: \$status (\$active_status)"
    fi
done

echo -e "\n=== Unbound服务状态 ==="
systemctl status unbound --no-pager -l
EOF

    chmod +x /usr/local/bin/check-dns-port.sh

    # 创建配置查看脚本
    cat > /usr/local/bin/show-unbound-config.sh << EOF
#!/bin/bash
# Unbound配置查看脚本

echo "=== Unbound 配置信息 ==="
echo "安装目录: /usr/local/"
echo "配置文件: $UNBOUND_CONFIG_DIR/unbound.conf"
echo "根提示文件: $UNBOUND_ROOT_HINTS"
echo "监听端口: $UNBOUND_PORT"
echo "服务状态: \$(systemctl is-active unbound)"

echo -e "\n=== 最近日志 ==="
journalctl -u unbound --no-pager -n 10

echo -e "\n=== 端口监听状态 ==="
ss -tulpn | grep ":$UNBOUND_PORT " || echo "端口 $UNBOUND_PORT 未监听"
EOF

    chmod +x /usr/local/bin/show-unbound-config.sh
}

# 显示安装摘要
show_install_summary() {
    echo -e "\n${GREEN}"
    echo "================================================"
    echo "           安装完成摘要"
    echo "================================================"
    echo -e "${NC}"
    
    echo -e "${GREEN}✓ Unbound 安装完成${NC}"
    echo -e "安装目录: /usr/local/"
    echo -e "配置文件: $UNBOUND_CONFIG_DIR/unbound.conf"
    echo -e "根提示文件: $UNBOUND_ROOT_HINTS"
    echo -e "监听端口: $UNBOUND_PORT"
    echo -e "服务状态: $(systemctl is-active unbound)"
    echo -e "运行模式: 纯递归（使用Yeti根服务器）"

    echo -e "\n${YELLOW}管理命令:${NC}"
    echo -e "启动服务: systemctl start unbound"
    echo -e "停止服务: systemctl stop unbound"
    echo -e "重启服务: systemctl restart unbound"
    echo -e "查看状态: systemctl status unbound"
    echo -e "查看日志: journalctl -u unbound -f"

    echo -e "\n${YELLOW}工具脚本:${NC}"
    echo -e "更新根提示: /usr/local/bin/update-yeti-root.sh"
    echo -e "端口检查: /usr/local/bin/check-dns-port.sh"
    echo -e "配置查看: /usr/local/bin/show-unbound-config.sh"
    echo -e "解析测试: /usr/local/sbin/unbound-host yeti-dns.org"

    if [ "$UNBOUND_PORT" != "53" ]; then
        echo -e "\n${RED}重要提醒:${NC}"
        echo -e "Unbound运行在非标准端口 $UNBOUND_PORT"
        echo -e "您需要手动配置客户端使用此端口进行DNS查询"
        echo -e "例如: dig @服务器IP -p $UNBOUND_PORT google.com"
    else
        echo -e "\n${GREEN}系统DNS配置:${NC}"
        echo -e "Unbound运行在标准DNS端口53"
        echo -e "可以将系统DNS设置为127.0.0.1使用本地解析"
    fi

    echo -e "\n${BLUE}Yeti DNS项目信息:${NC}"
    echo -e "官方网站: https://yeti-dns.org/"
    echo -e "根区文件: https://yeti-dns.org/rootzone.html"
    echo -e "GitHub: https://github.com/BII-Lab/Yeti-Project"

    echo -e "\n${YELLOW}安装完成时间: $(date)${NC}"
}

# 主安装流程
main() {
    # 获取用户输入
    get_user_input
    
    # 设置临时DNS
    setup_temporary_dns
    
    # 检查并处理端口占用
    check_port_usage
    
    # 安装依赖和Unbound
    install_unbound
    
    # 配置Unbound
    configure_unbound
    
    # 创建systemd服务
    setup_systemd_service
    
    # 配置防火墙
    setup_firewall
    
    # 启动和测试服务
    start_and_test_service
    
    # 创建工具脚本
    create_utility_scripts
    
    # 恢复原始DNS配置
    restore_original_dns
    
    # 显示安装摘要
    show_install_summary
}

# 运行主函数
main