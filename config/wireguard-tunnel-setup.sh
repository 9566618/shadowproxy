#!/bin/bash
# ============================================================
# WireGuard 隧道配置工具
# 用于在两台服务器之间建立 WireGuard 隧道，支持策略路由转发
# 
# 使用方式: 
#   交互模式:  ./wireguard-tunnel-setup.sh
#   参数模式: ./wireguard-tunnel-setup.sh [选项]
#
# 示例:
#   源端服务器 (转发端):
#     ./wireguard-tunnel-setup.sh -r source -l 10.200.200.1/24 \
#       -i eth0 -e 45.77.47.173 -k "对端公钥" -m 255 -t 100
#
#   目标服务器 (出口端):
#     ./wireguard-tunnel-setup.sh -r target -l 10.200.200.2/24 \
#       -i enp1s0 -e 38.147.184.89 -k "对端公钥" -s 10.200.200.0/24
# ============================================================

set -e

# ==================== 默认值 ====================
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_DIR="/etc/wireguard"
KEEPALIVE="25"

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }

# ==================== 帮助信息 ====================
show_help() {
    cat << 'EOF'
WireGuard 隧道配置工具

用法:  ./wireguard-tunnel-setup.sh [选项]

必选参数:
  -r, --role <source|target>    服务器角色
                                  source: 源端/转发端 (流量发起方)
                                  target: 目标端/出口端 (NAT出口方)
  -l, --local-ip <IP/MASK>      本机隧道IP (如:  10.200.200.1/24)
  -i, --interface <NAME>        物理网卡接口名 (如: eth0, enp1s0)
  -e, --endpoint <IP>           对端服务器公网IP

可选参数: 
  -k, --peer-key <KEY>          对端WireGuard公钥 (可稍后填写)
  -p, --port <PORT>             WireGuard监听端口 (默认: 51820)
  -w, --wg-interface <NAME>     WireGuard接口名 (默认: wg0)
  -m, --fwmark <MARK>           策略路由fwmark值 (仅source端, 默认: 255)
  -t, --table <ID>              策略路由表ID (仅source端, 默认: 100)
  -s, --source-net <CIDR>       源端隧道网段 (仅target端, 如:  10.200.200.0/24)
  -a, --allowed-ips <CIDR>      对端AllowedIPs (默认: source端0.0.0.0/0, target端自动)
      --keepalive <SEC>         PersistentKeepalive (默认:  25)
      --gen-key-only            仅生成密钥对并退出
      --show-config             显示当前配置并退出
      --uninstall               卸载WireGuard配置
  -y, --yes                     跳过确认提示
  -h, --help                    显示此帮助信息

示例: 

  1. 源端服务器 (香港, 转发 fwmark=255 的流量):
     ./wireguard-tunnel-setup.sh -r source -l 10.200.200.1/24 \
       -i eth0 -e 45.77.47.173 -m 255 -t 100

  2. 目标端服务器 (新加坡, NAT出口):
     ./wireguard-tunnel-setup.sh -r target -l 10.200.200.2/24 \
       -i enp1s0 -e 38.147.184.89 -s 10.200.200.0/24

  3. 仅生成密钥: 
     ./wireguard-tunnel-setup.sh --gen-key-only

  4. 交互模式:
     ./wireguard-tunnel-setup.sh

EOF
    exit 0
}

# ==================== 参数解析 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--role)
                ROLE="$2"; shift 2 ;;
            -l|--local-ip)
                LOCAL_WG_IP="$2"; shift 2 ;;
            -i|--interface)
                PHYSICAL_INTERFACE="$2"; shift 2 ;;
            -e|--endpoint)
                PEER_ENDPOINT="$2"; shift 2 ;;
            -k|--peer-key)
                PEER_PUBLIC_KEY="$2"; shift 2 ;;
            -p|--port)
                WG_PORT="$2"; shift 2 ;;
            -w|--wg-interface)
                WG_INTERFACE="$2"; shift 2 ;;
            -m|--fwmark)
                FWMARK="$2"; shift 2 ;;
            -t|--table)
                ROUTE_TABLE="$2"; shift 2 ;;
            -s|--source-net)
                SOURCE_NETWORK="$2"; shift 2 ;;
            -a|--allowed-ips)
                ALLOWED_IPS="$2"; shift 2 ;;
            --keepalive)
                KEEPALIVE="$2"; shift 2 ;;
            --gen-key-only)
                GEN_KEY_ONLY=true; shift ;;
            --show-config)
                SHOW_CONFIG=true; shift ;;
            --uninstall)
                UNINSTALL=true; shift ;;
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
    echo "         WireGuard 隧道配置工具 - 交互模式"
    echo "============================================================"
    echo ""

    # 角色选择
    if [[ -z "$ROLE" ]]; then
        echo "请选择服务器角色:"
        echo "  1) source - 源端/转发端 (流量发起方, 如运行代理服务的服务器)"
        echo "  2) target - 目标端/出口端 (NAT出口, 流量最终出口服务器)"
        echo ""
        read -p "请输入 [1/2]: " role_choice
        case $role_choice in
            1|source) ROLE="source" ;;
            2|target) ROLE="target" ;;
            *) log_error "无效选择"; exit 1 ;;
        esac
    fi

    # 本机隧道IP
    if [[ -z "$LOCAL_WG_IP" ]]; then
        if [[ "$ROLE" == "source" ]]; then
            default_ip="10.200.200.1/24"
        else
            default_ip="10.200.200.2/24"
        fi
        read -p "本机隧道IP [默认: $default_ip]: " LOCAL_WG_IP
        LOCAL_WG_IP="${LOCAL_WG_IP:-$default_ip}"
    fi

    # 物理接口
    if [[ -z "$PHYSICAL_INTERFACE" ]]; then
        echo ""
        echo "可用网络接口:"
        ip -o link show | awk -F': ' '{print "  " $2}' | grep -v "lo"
        echo ""
        read -p "物理网卡接口名:  " PHYSICAL_INTERFACE
    fi

    # 对端IP
    if [[ -z "$PEER_ENDPOINT" ]]; then
        read -p "对端服务器公网IP:  " PEER_ENDPOINT
    fi

    # 对端公钥
    if [[ -z "$PEER_PUBLIC_KEY" ]]; then
        read -p "对端WireGuard公钥 (可留空稍后填写): " PEER_PUBLIC_KEY
        PEER_PUBLIC_KEY="${PEER_PUBLIC_KEY:-PEER_PUBLIC_KEY_PLACEHOLDER}"
    fi

    # 源端特有配置
    if [[ "$ROLE" == "source" ]]; then
        if [[ -z "$FWMARK" ]]; then
            read -p "策略路由 fwmark 值 [默认: 255]: " FWMARK
            FWMARK="${FWMARK:-255}"
        fi
        if [[ -z "$ROUTE_TABLE" ]]; then
            read -p "策略路由表 ID [默认: 100]: " ROUTE_TABLE
            ROUTE_TABLE="${ROUTE_TABLE:-100}"
        fi
    fi

    # 目标端特有配置
    if [[ "$ROLE" == "target" ]]; then
        if [[ -z "$SOURCE_NETWORK" ]]; then
            # 从本机IP推断网段
            default_net=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//. 0\//')
            read -p "源端隧道网段 [默认:  $default_net]:  " SOURCE_NETWORK
            SOURCE_NETWORK="${SOURCE_NETWORK:-$default_net}"
        fi
    fi

    # WireGuard端口
    read -p "WireGuard 端口 [默认: $WG_PORT]:  " input_port
    WG_PORT="${input_port:-$WG_PORT}"
}

# ==================== 验证参数 ====================
validate_params() {
    local errors=0

    if [[ -z "$ROLE" ]] || [[ !  "$ROLE" =~ ^(source|target)$ ]]; then
        log_error "必须指定有效的角色:  source 或 target"
        errors=$((errors + 1))
    fi

    if [[ -z "$LOCAL_WG_IP" ]]; then
        log_error "必须指定本机隧道IP (-l)"
        errors=$((errors + 1))
    elif [[ ! "$LOCAL_WG_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        log_error "隧道IP格式无效，应为 x.x.x. x/xx"
        errors=$((errors + 1))
    fi

    if [[ -z "$PHYSICAL_INTERFACE" ]]; then
        log_error "必须指定物理网卡接口 (-i)"
        errors=$((errors + 1))
    elif !  ip link show "$PHYSICAL_INTERFACE" &>/dev/null; then
        log_warn "网卡接口 '$PHYSICAL_INTERFACE' 不存在，请确认"
    fi

    if [[ -z "$PEER_ENDPOINT" ]]; then
        log_error "必须指定对端服务器IP (-e)"
        errors=$((errors + 1))
    fi

    if [[ "$ROLE" == "source" ]]; then
        FWMARK="${FWMARK:-255}"
        ROUTE_TABLE="${ROUTE_TABLE:-100}"
        ALLOWED_IPS="${ALLOWED_IPS:-0.0.0.0/0}"
    fi

    if [[ "$ROLE" == "target" ]]; then
        if [[ -z "$SOURCE_NETWORK" ]]; then
            # 自动推断
            SOURCE_NETWORK=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.0\//')
            log_info "自动推断源端网段:  $SOURCE_NETWORK"
        fi
        # target端的AllowedIPs是源端IP
        if [[ -z "$ALLOWED_IPS" ]]; then
            ALLOWED_IPS=$(echo "$LOCAL_WG_IP" | sed 's/\/[0-9]*/\/32/' | sed 's/\. 2\//. 1\//')
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "使用 -h 查看帮助信息"
        exit 1
    fi
}

# ==================== 安装 WireGuard ====================
install_wireguard() {
    log_step "检查并安装 WireGuard..."
    
    if command -v wg &>/dev/null; then
        log_info "WireGuard 已安装"
        return 0
    fi

    # 检测发行版
    if [[ -f /etc/debian_version ]]; then
        apt update && apt install -y wireguard wireguard-tools
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y epel-release
        yum install -y wireguard-tools
    elif [[ -f /etc/arch-release ]]; then
        pacman -S --noconfirm wireguard-tools
    else
        log_error "未知的Linux发行版，请手动安装 wireguard-tools"
        exit 1
    fi

    log_info "WireGuard 安装完成"
}

# ==================== 生成密钥 ====================
generate_keys() {
    log_step "生成 WireGuard 密钥对..."
    
    mkdir -p "$WG_DIR"
    
    local key_prefix="${ROLE:-wg}"
    PRIVATE_KEY_FILE="${WG_DIR}/${key_prefix}_private.key"
    PUBLIC_KEY_FILE="${WG_DIR}/${key_prefix}_public.key"

    if [[ -f "$PRIVATE_KEY_FILE" ]] && [[ -f "$PUBLIC_KEY_FILE" ]]; then
        if [[ "$AUTO_CONFIRM" != "true" ]]; then
            read -p "密钥已存在，是否重新生成? [y/N]: " regen
            if [[ !  "$regen" =~ ^[Yy]$ ]]; then
                log_info "使用现有密钥"
                PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
                PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")
                return 0
            fi
        else
            log_info "使用现有密钥"
            PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
            PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")
            return 0
        fi
    fi

    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

    echo "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE"
    echo "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"
    chmod 600 "$PRIVATE_KEY_FILE"

    log_info "密钥已生成"
}

# ==================== 生成源端配置 ====================
generate_source_config() {
    log_step "生成源端 (转发端) WireGuard 配置..."

    cat > "${WG_DIR}/${WG_INTERFACE}. conf" << EOF
# ============================================================
# WireGuard 源端配置 (转发端)
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 角色: 将 fwmark=${FWMARK} 的流量通过隧道转发到目标端
# ============================================================

[Interface]
Address = ${LOCAL_WG_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}

# 禁止自动添加路由，使用策略路由
Table = off

# === 启动时执行 ===
# 添加策略路由:  fwmark=${FWMARK} 的包走路由表 ${ROUTE_TABLE}
PostUp = ip rule add fwmark ${FWMARK} table ${ROUTE_TABLE} priority 100
PostUp = ip route add default dev ${WG_INTERFACE} table ${ROUTE_TABLE}
# 确保 WireGuard 封装流量走物理接口
PostUp = ip rule add to ${PEER_ENDPOINT} lookup main priority 50

# === 关闭时清理 ===
PostDown = ip rule del fwmark ${FWMARK} table ${ROUTE_TABLE} priority 100 || true
PostDown = ip route del default dev ${WG_INTERFACE} table ${ROUTE_TABLE} || true
PostDown = ip rule del to ${PEER_ENDPOINT} lookup main priority 50 || true

[Peer]
# 目标端服务器 (出口)
PublicKey = ${PEER_PUBLIC_KEY}
Endpoint = ${PEER_ENDPOINT}: ${WG_PORT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${KEEPALIVE}
EOF

    chmod 600 "${WG_DIR}/${WG_INTERFACE}.conf"
    log_info "配置文件已生成:  ${WG_DIR}/${WG_INTERFACE}.conf"
}

# ==================== 生成目标端配置 ====================
generate_target_config() {
    log_step "生成目标端 (出口端) WireGuard 配置..."

    cat > "${WG_DIR}/${WG_INTERFACE}. conf" << EOF
# ============================================================
# WireGuard 目标端配置 (出口端)
# 生成时间:  $(date '+%Y-%m-%d %H:%M:%S')
# 角色: 接收隧道流量并 NAT 转发到互联网
# ============================================================

[Interface]
Address = ${LOCAL_WG_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}

# === 启动时执行 ===
# NAT:  隧道来源流量从物理接口出去时做地址伪装
PostUp = iptables -t nat -A POSTROUTING -s ${SOURCE_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE
# 允许转发
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT
PostUp = iptables -A FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT

# === 关闭时清理 ===
PostDown = iptables -t nat -D POSTROUTING -s ${SOURCE_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE || true
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT || true
PostDown = iptables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT || true

[Peer]
# 源端服务器 (转发端)
PublicKey = ${PEER_PUBLIC_KEY}
Endpoint = ${PEER_ENDPOINT}:${WG_PORT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${KEEPALIVE}
EOF

    chmod 600 "${WG_DIR}/${WG_INTERFACE}. conf"
    log_info "配置文件已生成: ${WG_DIR}/${WG_INTERFACE}.conf"
}

# ==================== 系统配置 ====================
configure_system() {
    log_step "配置系统参数..."

    # 启用 IP 转发
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    if !  grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    log_info "IP 转发已启用"

    # 防火墙规则
    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT
        log_info "防火墙已放行 UDP 端口 ${WG_PORT}"
    fi
}

# ==================== 启动服务 ====================
start_wireguard() {
    log_step "启动 WireGuard 服务..."

    # 停止可能存在的实例
    wg-quick down "${WG_INTERFACE}" 2>/dev/null || true

    # 启用并启动
    systemctl enable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    systemctl start "wg-quick@${WG_INTERFACE}"

    log_info "WireGuard 服务已启动"
}

# ==================== 显示摘要 ====================
show_summary() {
    local peer_ip
    peer_ip=$(echo "$LOCAL_WG_IP" | cut -d'/' -f1)

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}配置完成! ${NC}"
    echo "============================================================"
    echo ""
    echo "  角色:           ${ROLE} ($([ "$ROLE" == "source" ] && echo "转发端" || echo "出口端"))"
    echo "  WireGuard接口: ${WG_INTERFACE}"
    echo "  隧道IP:        ${LOCAL_WG_IP}"
    echo "  监听端口:      ${WG_PORT}"
    echo "  物理接口:      ${PHYSICAL_INTERFACE}"
    echo ""
    echo "  对端服务器:     ${PEER_ENDPOINT}:${WG_PORT}"
    if [[ "$ROLE" == "source" ]]; then
        echo "  策略路由:      fwmark=${FWMARK} -> table ${ROUTE_TABLE} -> ${WG_INTERFACE}"
    fi
    echo ""
    echo "------------------------------------------------------------"
    echo -e "  ${YELLOW}本机公钥 (复制给对端):${NC}"
    echo ""
    echo "  ${PUBLIC_KEY}"
    echo ""
    echo "------------------------------------------------------------"
    
    if [[ "$PEER_PUBLIC_KEY" == "PEER_PUBLIC_KEY_PLACEHOLDER" ]]; then
        echo -e "  ${RED}注意:  对端公钥未配置!${NC}"
        echo ""
        echo "  请获取对端公钥后编辑配置文件:"
        echo "    vim ${WG_DIR}/${WG_INTERFACE}.conf"
        echo ""
        echo "  替换 'PEER_PUBLIC_KEY_PLACEHOLDER' 为对端公钥"
        echo "  然后重启:  systemctl restart wg-quick@${WG_INTERFACE}"
        echo ""
    fi

    echo "------------------------------------------------------------"
    echo "  常用命令:"
    echo ""
    echo "    查看状态:    wg show"
    echo "    查看日志:   journalctl -u wg-quick@${WG_INTERFACE}"
    echo "    重启服务:   systemctl restart wg-quick@${WG_INTERFACE}"
    echo "    停止服务:   systemctl stop wg-quick@${WG_INTERFACE}"
    echo "    测试连通:    ping ${peer_ip/%. 1/. 2}"
    echo ""
    if [[ "$ROLE" == "source" ]]; then
        echo "  调试路由:"
        echo "    ip rule list"
        echo "    ip route show table ${ROUTE_TABLE}"
        echo "    ip route get 8.8.8.8 mark ${FWMARK}"
        echo ""
    fi
    echo "============================================================"
}

# ==================== 卸载 ====================
uninstall_wireguard() {
    log_warn "准备卸载 WireGuard 配置..."
    
    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        read -p "确定要卸载 ${WG_INTERFACE} 配置吗?  [y/N]:  " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "已取消"
            exit 0
        fi
    fi

    wg-quick down "${WG_INTERFACE}" 2>/dev/null || true
    systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true

    if [[ -f "${WG_DIR}/${WG_INTERFACE}.conf" ]]; then
        rm -f "${WG_DIR}/${WG_INTERFACE}.conf"
        log_info "已删除 ${WG_DIR}/${WG_INTERFACE}.conf"
    fi

    log_info "卸载完成"
    exit 0
}

# ==================== 显示当前配置 ====================
show_current_config() {
    if [[ -f "${WG_DIR}/${WG_INTERFACE}.conf" ]]; then
        echo ""
        echo "当前配置文件:  ${WG_DIR}/${WG_INTERFACE}.conf"
        echo "------------------------------------------------------------"
        cat "${WG_DIR}/${WG_INTERFACE}.conf"
        echo "------------------------------------------------------------"
        echo ""
        echo "WireGuard 状态:"
        wg show 2>/dev/null || echo "WireGuard 未运行"
    else
        log_warn "配置文件不存在:  ${WG_DIR}/${WG_INTERFACE}.conf"
    fi
    exit 0
}

# ==================== 仅生成密钥 ====================
gen_key_only() {
    mkdir -p "$WG_DIR"
    
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

    echo ""
    echo "============================================================"
    echo "  WireGuard 密钥对"
    echo "============================================================"
    echo ""
    echo "  私钥 (保密): ${PRIVATE_KEY}"
    echo ""
    echo "  公钥 (共享): ${PUBLIC_KEY}"
    echo ""
    echo "============================================================"
    
    read -p "是否保存到文件?  [y/N]:  " save
    if [[ "$save" =~ ^[Yy]$ ]]; then
        read -p "文件名前缀 [默认: wg]: " prefix
        prefix="${prefix:-wg}"
        echo "$PRIVATE_KEY" > "${WG_DIR}/${prefix}_private.key"
        echo "$PUBLIC_KEY" > "${WG_DIR}/${prefix}_public.key"
        chmod 600 "${WG_DIR}/${prefix}_private.key"
        log_info "已保存到 ${WG_DIR}/${prefix}_private.key 和 ${WG_DIR}/${prefix}_public.key"
    fi
    
    exit 0
}

# ==================== 主函数 ====================
main() {
    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        echo "  sudo $0 $*"
        exit 1
    fi

    # 解析参数
    parse_args "$@"

    # 特殊操作
    [[ "$GEN_KEY_ONLY" == "true" ]] && gen_key_only
    [[ "$SHOW_CONFIG" == "true" ]] && show_current_config
    [[ "$UNINSTALL" == "true" ]] && uninstall_wireguard

    # 如果没有足够参数，进入交互模式
    if [[ -z "$ROLE" ]] || [[ -z "$LOCAL_WG_IP" ]] || [[ -z "$PHYSICAL_INTERFACE" ]] || [[ -z "$PEER_ENDPOINT" ]]; then
        interactive_input
    fi

    # 验证参数
    validate_params

    # 确认配置
    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        echo ""
        echo "即将应用以下配置:"
        echo "  角色:  $ROLE"
        echo "  隧道IP: $LOCAL_WG_IP"
        echo "  物理接口: $PHYSICAL_INTERFACE"
        echo "  对端:  $PEER_ENDPOINT: $WG_PORT"
        [[ "$ROLE" == "source" ]] && echo "  策略路由:  fwmark=$FWMARK -> table $ROUTE_TABLE"
        echo ""
        read -p "继续?  [Y/n]: " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            log_info "已取消"
            exit 0
        fi
    fi

    # 执行配置
    install_wireguard
    generate_keys

    if [[ "$ROLE" == "source" ]]; then
        generate_source_config
    else
        generate_target_config
    fi

    configure_system
    start_wireguard
    show_summary
}

# 运行
main "$@"
