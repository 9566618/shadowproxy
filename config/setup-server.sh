#!/bin/bash
# ============================================================
# Shadowsocks-rust 服务端一键部署脚本
# 适用于 x86_64-gnu Linux 服务器
#
# 使用方式:
#   交互模式:  ./setup-server.sh
#   参数模式:  ./setup-server.sh -p <端口> -k <密码> [-m <加密方式>]
#
# 示例:
#   ./setup-server.sh -p 8388 -k "my_secure_password" -m aes-256-gcm
# ============================================================

set -e

# ==================== 默认配置 ====================
SS_PORT="8388"
SS_PASSWORD=""
SS_METHOD="aes-256-gcm"
SS_TIMEOUT="300"
WORKER_COUNT="16"
NOFILE="32768"

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/shadowsocks"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(dirname "$SCRIPT_DIR")/bin/x86_64-gnu"

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }

# ==================== 帮助信息 ====================
show_help() {
    cat << 'EOF'
Shadowsocks-rust 服务端部署脚本

用法: ./setup-server.sh [选项]

选项:
  -p, --port <PORT>         服务端口 (默认: 8388)
  -k, --password <PASS>     连接密码 (必填，或交互输入)
  -m, --method <METHOD>     加密方式 (默认: aes-256-gcm)
  -w, --workers <NUM>       工作线程数 (默认: 16)
  -t, --timeout <SEC>       UDP 超时时间 (默认: 300)
      --uninstall           卸载 Shadowsocks 服务
  -y, --yes                 跳过确认提示
  -h, --help                显示此帮助信息

支持的加密方式:
  推荐: aes-256-gcm, aes-128-gcm, chacha20-ietf-poly1305
  其他: aes-256-cfb, aes-128-cfb, rc4-md5 等

示例:
  ./setup-server.sh -p 8388 -k "my_password"
  ./setup-server.sh -p 443 -k "password" -m chacha20-ietf-poly1305
  ./setup-server.sh --uninstall

EOF
    exit 0
}

# ==================== 参数解析 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--port)
                SS_PORT="$2"; shift 2 ;;
            -k|--password)
                SS_PASSWORD="$2"; shift 2 ;;
            -m|--method)
                SS_METHOD="$2"; shift 2 ;;
            -w|--workers)
                WORKER_COUNT="$2"; shift 2 ;;
            -t|--timeout)
                SS_TIMEOUT="$2"; shift 2 ;;
            --uninstall)
                do_uninstall; exit 0 ;;
            -y|--yes)
                AUTO_CONFIRM=true; shift ;;
            -h|--help)
                show_help ;;
            *)
                log_error "未知参数: $1"
                echo "使用 -h 或 --help 查看帮助"
                exit 1 ;;
        esac
    done
}

# ==================== 交互式输入 ====================
interactive_input() {
    echo ""
    echo "============================================================"
    echo "       Shadowsocks-rust 服务端部署脚本"
    echo "============================================================"
    echo ""

    # 端口
    if [[ -z "$SS_PORT" ]] || [[ "$SS_PORT" == "8388" ]]; then
        read -p "服务端口 [默认: 8388]: " input_port
        SS_PORT="${input_port:-8388}"
    fi

    # 密码
    if [[ -z "$SS_PASSWORD" ]]; then
        while true; do
            read -sp "连接密码: " SS_PASSWORD
            echo ""
            if [[ -n "$SS_PASSWORD" ]]; then
                break
            fi
            log_warn "密码不能为空"
        done
    fi

    # 加密方式
    echo ""
    echo "加密方式:"
    echo "  1) aes-256-gcm (推荐)"
    echo "  2) aes-128-gcm"
    echo "  3) chacha20-ietf-poly1305"
    echo "  4) 自定义"
    read -p "请选择 [默认: 1]: " method_choice
    case $method_choice in
        2) SS_METHOD="aes-128-gcm" ;;
        3) SS_METHOD="chacha20-ietf-poly1305" ;;
        4) read -p "输入加密方式: " SS_METHOD ;;
        *) SS_METHOD="aes-256-gcm" ;;
    esac

    # 工作线程
    read -p "工作线程数 [默认: 16]: " input_workers
    WORKER_COUNT="${input_workers:-16}"
}

# ==================== 检查环境 ====================
check_environment() {
    log_step "检查环境..."

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi

    # 检查系统架构
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        log_error "此脚本仅支持 x86_64 架构，当前架构: $ARCH"
        exit 1
    fi

    # 检查 ssserver 文件
    if [[ ! -f "$BIN_DIR/ssserver" ]]; then
        log_error "找不到 ssserver 文件: $BIN_DIR/ssserver"
        exit 1
    fi

    # 检查 systemd
    if ! command -v systemctl &> /dev/null; then
        log_warn "未检测到 systemd，将跳过服务配置"
        NO_SYSTEMD=true
    fi

    log_info "环境检查通过"
}

# ==================== 生成配置文件 ====================
generate_config() {
    log_step "生成配置文件..."

    mkdir -p "$CONFIG_DIR"

    # 生成 config.json
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "servers": [
    {
      "server": "::",
      "server_port": ${SS_PORT},
      "password": "${SS_PASSWORD}",
      "method": "${SS_METHOD}",
      "mode": "tcp_and_udp"
    }
  ],

  "nofile": ${NOFILE},
  "ipv6_first": false,
  "ipv6_only": false,
  "outbound_fwmark": 255,
  "udp_timeout": ${SS_TIMEOUT},

  "security": {
    "replay_attack": {
      "policy": "reject"
    }
  },

  "log": {
    "config_path": "${CONFIG_DIR}/log4rs.yml"
  },

  "runtime": {
    "mode": "multi_thread",
    "worker_count": ${WORKER_COUNT}
  }
}
EOF

    # 生成 log4rs.yml
    cat > "$CONFIG_DIR/log4rs.yml" << 'EOF'
refresh_rate: 30 seconds
appenders:
  stdout:
    kind: console
    encoder:
      pattern: "{d} {h({l}):<5} {m}{n}"
  file:
    kind: rolling_file
    path: /var/log/shadowsocks/ssserver.log
    encoder:
      kind: pattern
      pattern: "{d} {h({l}):<5} {m}{n}"
    policy:
      trigger:
        kind: size
        limit: 50 mb
      roller:
        kind: fixed_window
        pattern: /var/log/shadowsocks/ssserver.{}.log
        count: 5
root:
  level: info
  appenders:
    - file
EOF

    # 创建日志目录
    mkdir -p /var/log/shadowsocks

    log_info "配置文件已生成: $CONFIG_DIR/config.json"
}

# ==================== 安装二进制文件 ====================
install_binary() {
    log_step "安装 ssserver..."

    cp "$BIN_DIR/ssserver" "$INSTALL_DIR/ssserver"
    chmod +x "$INSTALL_DIR/ssserver"

    log_info "ssserver 已安装到: $INSTALL_DIR/ssserver"
}

# ==================== 配置 systemd 服务 ====================
setup_systemd() {
    if [[ "$NO_SYSTEMD" == "true" ]]; then
        log_warn "跳过 systemd 服务配置"
        return
    fi

    log_step "配置 systemd 服务..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Shadowsocks-rust Server
Documentation=https://github.com/shadowsocks/shadowsocks-rust
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
LimitNOFILE=${NOFILE}
LimitNPROC=${NOFILE}
ExecStart=${INSTALL_DIR}/ssserver -c ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5
StandardOutput=null
StandardError=journal

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/shadowsocks
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocks
    
    log_info "systemd 服务已配置"
}

# ==================== 配置防火墙 ====================
setup_firewall() {
    log_step "配置防火墙..."

    # 检测防火墙类型
    if command -v ufw &> /dev/null; then
        ufw allow ${SS_PORT}/tcp
        ufw allow ${SS_PORT}/udp
        log_info "UFW 规则已添加"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${SS_PORT}/tcp
        firewall-cmd --permanent --add-port=${SS_PORT}/udp
        firewall-cmd --reload
        log_info "firewalld 规则已添加"
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport ${SS_PORT} -j ACCEPT
        iptables -A INPUT -p udp --dport ${SS_PORT} -j ACCEPT
        log_info "iptables 规则已添加 (需手动保存)"
    else
        log_warn "未检测到防火墙，请手动开放端口 ${SS_PORT}"
    fi
}

# ==================== 优化系统参数 ====================
optimize_sysctl() {
    log_step "优化系统参数..."

    SYSCTL_CONF="/etc/sysctl.d/99-shadowsocks.conf"

    cat > "$SYSCTL_CONF" << 'EOF'
# Shadowsocks 优化参数

# 网络缓冲区
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096

# TCP 优化
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = bbr

# UDP 优化
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 文件描述符
fs.file-max = 1048576

# 启用 IP 转发 (可选，用于 WireGuard)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    # 检查是否支持 BBR
    if modprobe tcp_bbr 2>/dev/null; then
        log_info "已启用 TCP BBR 拥塞控制"
    else
        sed -i '/tcp_congestion_control/d' "$SYSCTL_CONF"
        log_warn "内核不支持 BBR，已跳过"
    fi

    sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1

    log_info "系统参数优化完成"
}

# ==================== 启动服务 ====================
start_service() {
    if [[ "$NO_SYSTEMD" == "true" ]]; then
        log_info "请手动启动: $INSTALL_DIR/ssserver -c $CONFIG_DIR/config.json"
        return
    fi

    log_step "启动服务..."

    systemctl start shadowsocks

    sleep 2

    if systemctl is-active --quiet shadowsocks; then
        log_info "Shadowsocks 服务已启动"
    else
        log_error "服务启动失败，请检查日志: journalctl -u shadowsocks"
        exit 1
    fi
}

# ==================== 显示连接信息 ====================
show_connection_info() {
    echo ""
    echo "============================================================"
    echo -e "${GREEN}        Shadowsocks 服务端部署完成！${NC}"
    echo "============================================================"
    echo ""
    echo "连接信息:"
    echo "  服务器地址:  $(curl -s4 ip.sb 2>/dev/null || hostname -I | awk '{print $1}')"
    echo "  端口:        ${SS_PORT}"
    echo "  密码:        ${SS_PASSWORD}"
    echo "  加密方式:    ${SS_METHOD}"
    echo ""
    echo "服务管理:"
    echo "  启动:   systemctl start shadowsocks"
    echo "  停止:   systemctl stop shadowsocks"
    echo "  重启:   systemctl restart shadowsocks"
    echo "  状态:   systemctl status shadowsocks"
    echo "  日志:   journalctl -u shadowsocks -f"
    echo ""
    echo "配置文件:  ${CONFIG_DIR}/config.json"
    echo "============================================================"
}

# ==================== 卸载 ====================
do_uninstall() {
    log_step "卸载 Shadowsocks..."

    if [[ "$NO_SYSTEMD" != "true" ]]; then
        systemctl stop shadowsocks 2>/dev/null || true
        systemctl disable shadowsocks 2>/dev/null || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    rm -f "$INSTALL_DIR/ssserver"
    rm -rf "$CONFIG_DIR"
    rm -f /etc/sysctl.d/99-shadowsocks.conf

    log_info "Shadowsocks 已卸载"
}

# ==================== 确认安装 ====================
confirm_install() {
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return
    fi

    echo ""
    echo "即将安装 Shadowsocks 服务端:"
    echo "  端口:       ${SS_PORT}"
    echo "  加密方式:   ${SS_METHOD}"
    echo "  工作线程:   ${WORKER_COUNT}"
    echo ""
    read -p "确认安装? [Y/n]: " confirm
    case $confirm in
        [Nn]*) log_info "已取消"; exit 0 ;;
    esac
}

# ==================== 主函数 ====================
main() {
    parse_args "$@"

    # 如果没有提供密码，进入交互模式
    if [[ -z "$SS_PASSWORD" ]]; then
        interactive_input
    fi

    check_environment
    confirm_install
    install_binary
    generate_config
    setup_systemd
    setup_firewall
    optimize_sysctl
    start_service
    show_connection_info
}

main "$@"
