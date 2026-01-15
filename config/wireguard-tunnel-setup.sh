#!/bin/bash
# ============================================================
# WireGuard 隧道配置工具 (IPv4/IPv6 双栈版)
# ============================================================

set -e

# ==================== 默认值 ====================
WG_INTERFACE="wg0"
WG_PORT="51820"
WG_DIR="/etc/wireguard"
KEEPALIVE="25"
ENABLE_IPV6="auto"

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ==================== 帮助信息 ====================
show_help() {
    cat << 'EOF'
WireGuard 隧道配置工具 (IPv4/IPv6 双栈版)

用法: ./wireguard-tunnel-setup.sh [选项]

必选参数:
  -r, --role <source|target>    服务器角色
                                  source: 源端/转发端 (流量发起方)
                                  target: 目标端/出口端 (NAT出口方)
  -l, --local-ip <IP/MASK>      本机隧道IPv4 (如: 10.200.200.1/24)
  -i, --interface <NAME>        物理网卡接口名 (如: eth0, enp1s0)
  -e, --endpoint <IP>           对端服务器公网IP (IPv4或IPv6)

IPv6 参数:
  -6, --local-ip6 <IP/MASK>     本机隧道IPv6 (如: fd00:200::1/64)
  -E, --endpoint6 <IP>          对端服务器公网IPv6
  -S, --source-net6 <CIDR>      源端隧道IPv6网段 (仅target端)
      --ipv6 <auto|yes|no>      IPv6模式 (默认: auto)

可选参数:
  -k, --peer-key <KEY>          对端WireGuard公钥 (可稍后填写)
  -p, --port <PORT>             WireGuard监听端口 (默认: 51820)
  -w, --wg-interface <NAME>     WireGuard接口名 (默认: wg0)
  -m, --fwmark <MARK>           策略路由fwmark值 (仅source端, 默认: 255)
  -t, --table <ID>              策略路由表ID (仅source端, 默认: 100)
  -s, --source-net <CIDR>       源端隧道IPv4网段 (仅target端)
  -a, --allowed-ips <CIDR>      对端AllowedIPs (自动生成)
      --keepalive <SEC>         PersistentKeepalive (默认: 25)
      --gen-key-only            仅生成密钥对并退出
      --show-config             显示当前配置并退出
      --uninstall               卸载WireGuard配置
  -y, --yes                     跳过确认提示
  -h, --help                    显示此帮助信息

示例:
  # 仅IPv4 - 源端
  ./wireguard-tunnel-setup.sh -r source -l 10.200.200.1/24 -i eth0 -e 45.77.47.173

  # IPv4+IPv6 双栈 - 源端
  ./wireguard-tunnel-setup.sh -r source -l 10.200.200.1/24 -6 fd00:200::1/64 \
    -i eth0 -e 45.77.47.173 -E 2001:db8::2

EOF
    exit 0
}

# ==================== 参数解析 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--role)           ROLE="$2"; shift 2 ;;
            -l|--local-ip)       LOCAL_WG_IP="$2"; shift 2 ;;
            -6|--local-ip6)      LOCAL_WG_IP6="$2"; shift 2 ;;
            -i|--interface)      PHYSICAL_INTERFACE="$2"; shift 2 ;;
            -e|--endpoint)       PEER_ENDPOINT="$2"; shift 2 ;;
            -E|--endpoint6)      PEER_ENDPOINT6="$2"; shift 2 ;;
            -k|--peer-key)       PEER_PUBLIC_KEY="$2"; shift 2 ;;
            -p|--port)           WG_PORT="$2"; shift 2 ;;
            -w|--wg-interface)   WG_INTERFACE="$2"; shift 2 ;;
            -m|--fwmark)         FWMARK="$2"; shift 2 ;;
            -t|--table)          ROUTE_TABLE="$2"; shift 2 ;;
            -s|--source-net)     SOURCE_NETWORK="$2"; shift 2 ;;
            -S|--source-net6)    SOURCE_NETWORK6="$2"; shift 2 ;;
            -a|--allowed-ips)    ALLOWED_IPS="$2"; shift 2 ;;
            --ipv6)              ENABLE_IPV6="$2"; shift 2 ;;
            --keepalive)         KEEPALIVE="$2"; shift 2 ;;
            --gen-key-only)      GEN_KEY_ONLY=true; shift ;;
            --show-config)       SHOW_CONFIG=true; shift ;;
            --uninstall)         UNINSTALL=true; shift ;;
            -y|--yes)            AUTO_CONFIRM=true; shift ;;
            -h|--help)           show_help ;;
            *) log_error "未知参数: $1"; exit 1 ;;
        esac
    done
}

# ==================== IPv6 检测 ====================
detect_ipv6_support() {
    if [[ "$ENABLE_IPV6" == "no" ]]; then
        HAS_IPV6=false
        return
    fi

    if [[ "$ENABLE_IPV6" == "yes" ]]; then
        HAS_IPV6=true
        return
    fi

    if [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
        local disabled
        disabled=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
        if [[ "$disabled" == "0" ]]; then
            HAS_IPV6=true
            log_info "检测到系统支持 IPv6"
        else
            HAS_IPV6=false
            log_warn "系统 IPv6 已禁用"
        fi
    else
        HAS_IPV6=false
    fi

    if [[ -n "$LOCAL_WG_IP6" ]] || [[ -n "$PEER_ENDPOINT6" ]]; then
        HAS_IPV6=true
    fi
}

# ==================== 交互式输入 ====================
interactive_input() {
    echo ""
    echo "============================================================"
    echo "     WireGuard 隧道配置工具 - 交互模式 (IPv4/IPv6 双栈)"
    echo "============================================================"
    echo ""

    if [[ -z "$ROLE" ]]; then
        echo "请选择服务器角色:"
        echo "  1) source - 源端/转发端 (流量发起方)"
        echo "  2) target - 目标端/出口端 (NAT出口)"
        read -p "请输入 [1/2]: " role_choice
        case $role_choice in
            1|source) ROLE="source" ;;
            2|target) ROLE="target" ;;
            *) log_error "无效选择"; exit 1 ;;
        esac
    fi

    if [[ -z "$LOCAL_WG_IP" ]]; then
        if [[ "$ROLE" == "source" ]]; then
            default_ip="10.200.200.1/24"
        else
            default_ip="10.200.200.2/24"
        fi
        read -p "本机隧道 IPv4 [默认: $default_ip]: " LOCAL_WG_IP
        LOCAL_WG_IP="${LOCAL_WG_IP:-$default_ip}"
    fi

    echo ""
    read -p "是否配置 IPv6?  [y/N]: " enable_v6
    if [[ "$enable_v6" =~ ^[Yy]$ ]]; then
        HAS_IPV6=true
        if [[ -z "$LOCAL_WG_IP6" ]]; then
            if [[ "$ROLE" == "source" ]]; then
                default_ip6="fd00:200::1/64"
            else
                default_ip6="fd00:200::2/64"
            fi
            read -p "本机隧道 IPv6 [默认: $default_ip6]:  " LOCAL_WG_IP6
            LOCAL_WG_IP6="${LOCAL_WG_IP6:-$default_ip6}"
        fi
    else
        HAS_IPV6=false
    fi

    if [[ -z "$PHYSICAL_INTERFACE" ]]; then
        echo ""
        echo "可用网络接口:"
        ip -o link show | awk -F':  ' '{print "  " $2}' | grep -v "lo"
        read -p "物理网卡接口名:  " PHYSICAL_INTERFACE
    fi

    if [[ -z "$PEER_ENDPOINT" ]]; then
        read -p "对端服务器公网 IPv4: " PEER_ENDPOINT
    fi

    if [[ "$HAS_IPV6" == "true" ]] && [[ -z "$PEER_ENDPOINT6" ]]; then
        read -p "对端服务器公网 IPv6 (可选): " PEER_ENDPOINT6
    fi

    if [[ -z "$PEER_PUBLIC_KEY" ]]; then
        read -p "对端WireGuard公钥 (可留空): " PEER_PUBLIC_KEY
        PEER_PUBLIC_KEY="${PEER_PUBLIC_KEY:-PEER_PUBLIC_KEY_PLACEHOLDER}"
    fi

    if [[ "$ROLE" == "source" ]]; then
        if [[ -z "$FWMARK" ]]; then
            read -p "策略路由 fwmark 值 [默认: 255]:  " FWMARK
            FWMARK="${FWMARK:-255}"
        fi
        if [[ -z "$ROUTE_TABLE" ]]; then
            read -p "策略路由表 ID [默认: 100]: " ROUTE_TABLE
            ROUTE_TABLE="${ROUTE_TABLE:-100}"
        fi
    fi

    if [[ "$ROLE" == "target" ]]; then
        if [[ -z "$SOURCE_NETWORK" ]]; then
            default_net=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.0\//')
            read -p "源端隧道 IPv4 网段 [默认: $default_net]: " SOURCE_NETWORK
            SOURCE_NETWORK="${SOURCE_NETWORK:-$default_net}"
        fi
        if [[ "$HAS_IPV6" == "true" ]] && [[ -z "$SOURCE_NETWORK6" ]]; then
            read -p "源端隧道 IPv6 网段 [默认: fd00:200::/64]: " SOURCE_NETWORK6
            SOURCE_NETWORK6="${SOURCE_NETWORK6:-fd00:200::/64}"
        fi
    fi

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
        log_error "必须指定本机隧道 IPv4 (-l)"
        errors=$((errors + 1))
    elif [[ ! "$LOCAL_WG_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        log_error "隧道 IPv4 格式无效，应为 x.x.x.x/xx"
        errors=$((errors + 1))
    fi

    if [[ -n "$LOCAL_WG_IP6" ]]; then
        if [[ ! "$LOCAL_WG_IP6" =~ .*/.* ]]; then
            log_error "隧道 IPv6 格式无效，应包含前缀长度 (如: fd00:200::1/64)"
            errors=$((errors + 1))
        fi
    fi

    if [[ -z "$PHYSICAL_INTERFACE" ]]; then
        log_error "必须指定物理网卡接口 (-i)"
        errors=$((errors + 1))
    elif !  ip link show "$PHYSICAL_INTERFACE" &>/dev/null; then
        log_warn "网卡接口 '$PHYSICAL_INTERFACE' 不存在，请确认"
    fi

    if [[ -z "$PEER_ENDPOINT" ]] && [[ -z "$PEER_ENDPOINT6" ]]; then
        log_error "必须指定对端服务器 IP (-e 或 -E)"
        errors=$((errors + 1))
    fi

    if [[ "$ROLE" == "source" ]]; then
        FWMARK="${FWMARK:-255}"
        ROUTE_TABLE="${ROUTE_TABLE:-100}"
    fi

    if [[ "$ROLE" == "target" ]]; then
        if [[ -z "$SOURCE_NETWORK" ]]; then
            SOURCE_NETWORK=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.0\//')
            log_info "自动推断源端 IPv4 网段:  $SOURCE_NETWORK"
        fi
        if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]] && [[ -z "$SOURCE_NETWORK6" ]]; then
            SOURCE_NETWORK6="fd00:200::/64"
            log_info "使用默认源端 IPv6 网段:  $SOURCE_NETWORK6"
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        echo "使用 -h 查看帮助信息"
        exit 1
    fi
}

# ==================== 构建 AllowedIPs ====================
build_allowed_ips() {
    local ips=""

    if [[ "$ROLE" == "source" ]]; then
        ips="0.0.0.0/0"
        if [[ "$HAS_IPV6" == "true" ]]; then
            ips="${ips}, ::/0"
        fi
    else
        local peer_ip4
        peer_ip4=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.1\//' | sed 's/\/[0-9]*/\/32/')
        ips="$peer_ip4"

        if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]]; then
            local peer_ip6
            peer_ip6=$(echo "$LOCAL_WG_IP6" | sed 's/::[0-9a-fA-F]*\//::1\//' | sed 's/\/[0-9]*/\/128/')
            ips="${ips}, $peer_ip6"
        fi
    fi

    ALLOWED_IPS="${ALLOWED_IPS:-$ips}"
}

# ==================== 确定 Endpoint ====================
get_endpoint() {
    if [[ -n "$PEER_ENDPOINT" ]]; then
        EFFECTIVE_ENDPOINT="${PEER_ENDPOINT}:${WG_PORT}"
    elif [[ -n "$PEER_ENDPOINT6" ]]; then
        EFFECTIVE_ENDPOINT="[${PEER_ENDPOINT6}]:${WG_PORT}"
    fi
}

# ==================== 构建地址列表 ====================
build_address_list() {
    ADDRESS_LIST="$LOCAL_WG_IP"
    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]]; then
        ADDRESS_LIST="${ADDRESS_LIST}, ${LOCAL_WG_IP6}"
    fi
}

# ==================== 安装 WireGuard ====================
install_wireguard() {
    log_step "检查并安装 WireGuard..."

    if command -v wg &>/dev/null; then
        log_info "WireGuard 已安装"
        return 0
    fi

    if [[ -f /etc/debian_version ]]; then
        apt update && apt install -y wireguard wireguard-tools
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y epel-release
        yum install -y wireguard-tools
    elif [[ -f /etc/arch-release ]]; then
        pacman -S --noconfirm wireguard-tools
    elif command -v apk &>/dev/null; then
        apk add wireguard-tools
    else
        log_error "未知发行版，请手动安装 wireguard-tools"
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
            read -p "密钥已存在，是否重新生成?  [y/N]:  " regen
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

    build_address_list
    build_allowed_ips
    get_endpoint

    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"

    cat > "$config_file" << EOF
# ============================================================
# WireGuard 源端配置 (转发端) - IPv4/IPv6 双栈
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 角色: 将 fwmark=${FWMARK} 的流量通过隧道转发到目标端
# ============================================================

[Interface]
Address = ${ADDRESS_LIST}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}
Table = off

# === IPv4 策略路由 ===
PostUp = ip rule del fwmark ${FWMARK} table ${ROUTE_TABLE} 2>/dev/null || true
PostUp = ip rule add fwmark ${FWMARK} table ${ROUTE_TABLE} priority 100
PostUp = ip route replace default dev ${WG_INTERFACE} table ${ROUTE_TABLE}
EOF

    if [[ -n "$PEER_ENDPOINT" ]]; then
        cat >> "$config_file" << EOF
PostUp = ip rule del to ${PEER_ENDPOINT}/32 lookup main 2>/dev/null || true
PostUp = ip rule add to ${PEER_ENDPOINT}/32 lookup main priority 50
EOF
    fi

    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]]; then
        cat >> "$config_file" << EOF

# === IPv6 策略路由 ===
PostUp = ip -6 rule del fwmark ${FWMARK} table ${ROUTE_TABLE} 2>/dev/null || true
PostUp = ip -6 rule add fwmark ${FWMARK} table ${ROUTE_TABLE} priority 100
PostUp = ip -6 route replace default dev ${WG_INTERFACE} table ${ROUTE_TABLE}
EOF
        if [[ -n "$PEER_ENDPOINT6" ]]; then
            cat >> "$config_file" << EOF
PostUp = ip -6 rule del to ${PEER_ENDPOINT6}/128 lookup main 2>/dev/null || true
PostUp = ip -6 rule add to ${PEER_ENDPOINT6}/128 lookup main priority 50
EOF
        fi
    fi

    cat >> "$config_file" << EOF

# === 关闭时清理 ===
PostDown = ip rule del fwmark ${FWMARK} table ${ROUTE_TABLE} 2>/dev/null || true
PostDown = ip route del default dev ${WG_INTERFACE} table ${ROUTE_TABLE} 2>/dev/null || true
EOF

    if [[ -n "$PEER_ENDPOINT" ]]; then
        echo "PostDown = ip rule del to ${PEER_ENDPOINT}/32 lookup main 2>/dev/null || true" >> "$config_file"
    fi

    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]]; then
        cat >> "$config_file" << EOF
PostDown = ip -6 rule del fwmark ${FWMARK} table ${ROUTE_TABLE} 2>/dev/null || true
PostDown = ip -6 route del default dev ${WG_INTERFACE} table ${ROUTE_TABLE} 2>/dev/null || true
EOF
        if [[ -n "$PEER_ENDPOINT6" ]]; then
            echo "PostDown = ip -6 rule del to ${PEER_ENDPOINT6}/128 lookup main 2>/dev/null || true" >> "$config_file"
        fi
    fi

    cat >> "$config_file" << EOF

[Peer]
PublicKey = ${PEER_PUBLIC_KEY}
Endpoint = ${EFFECTIVE_ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${KEEPALIVE}
EOF

    chmod 600 "$config_file"
    log_info "配置文件已生成:  $config_file"
}

# ==================== 生成目标端配置 ====================
generate_target_config() {
    log_step "生成目标端 (出口端) WireGuard 配置..."

    build_address_list
    build_allowed_ips
    get_endpoint

    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"

    cat > "$config_file" << EOF
# ============================================================
# WireGuard 目标端配置 (出口端) - IPv4/IPv6 双栈
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 角色: 接收隧道流量并 NAT 转发到互联网
# ============================================================

[Interface]
Address = ${ADDRESS_LIST}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}

# === IPv4 NAT 和转发 ===
PostUp = iptables -t nat -D POSTROUTING -s ${SOURCE_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostUp = iptables -t nat -A POSTROUTING -s ${SOURCE_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE
PostUp = iptables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT
PostUp = iptables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
PostUp = iptables -A FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$SOURCE_NETWORK6" ]]; then
        cat >> "$config_file" << EOF

# === IPv6 NAT 和转发 ===
PostUp = ip6tables -t nat -D POSTROUTING -s ${SOURCE_NETWORK6} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostUp = ip6tables -t nat -A POSTROUTING -s ${SOURCE_NETWORK6} -o ${PHYSICAL_INTERFACE} -j MASQUERADE
PostUp = ip6tables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostUp = ip6tables -A FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT
PostUp = ip6tables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
PostUp = ip6tables -A FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF
    fi

    cat >> "$config_file" << EOF

# === 关闭时清理 ===
PostDown = iptables -t nat -D POSTROUTING -s ${SOURCE_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
EOF

    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$SOURCE_NETWORK6" ]]; then
        cat >> "$config_file" << EOF
PostDown = ip6tables -t nat -D POSTROUTING -s ${SOURCE_NETWORK6} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostDown = ip6tables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostDown = ip6tables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
EOF
    fi

    cat >> "$config_file" << EOF

[Peer]
PublicKey = ${PEER_PUBLIC_KEY}
Endpoint = ${EFFECTIVE_ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${KEEPALIVE}
EOF

    chmod 600 "$config_file"
    log_info "配置文件已生成:  $config_file"
}

# ==================== 系统配置 ====================
configure_system() {
    log_step "配置系统参数..."

    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    if !  grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    log_info "IPv4 转发已启用"

    if [[ "$HAS_IPV6" == "true" ]]; then
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
        if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
        fi
        log_info "IPv6 转发已启用"
    fi

    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT
        log_info "防火墙已放行 UDP 端口 ${WG_PORT} (IPv4)"
    fi

    if [[ "$HAS_IPV6" == "true" ]] && command -v ip6tables &>/dev/null; then
        ip6tables -C INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || \
        ip6tables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT
        log_info "防火墙已放行 UDP 端口 ${WG_PORT} (IPv6)"
    fi
}

# ==================== 启动服务 ====================
start_wireguard() {
    log_step "启动 WireGuard 服务..."

    wg-quick down "${WG_INTERFACE}" 2>/dev/null || true
    
    # 清理可能残留的路由规则
    if [[ "$ROLE" == "source" ]]; then
        ip rule del fwmark "${FWMARK}" table "${ROUTE_TABLE}" 2>/dev/null || true
        ip route del default table "${ROUTE_TABLE}" 2>/dev/null || true
        if [[ "$HAS_IPV6" == "true" ]]; then
            ip -6 rule del fwmark "${FWMARK}" table "${ROUTE_TABLE}" 2>/dev/null || true
            ip -6 route del default table "${ROUTE_TABLE}" 2>/dev/null || true
        fi
    fi

    systemctl enable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    systemctl start "wg-quick@${WG_INTERFACE}"

    log_info "WireGuard 服务已启动"
}

# ==================== 显示摘要 ====================
show_summary() {
    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}配置完成! ${NC}"
    echo "============================================================"
    echo ""
    echo "  角色:             ${ROLE}"
    echo "  WireGuard接口:   ${WG_INTERFACE}"
    echo "  隧道 IPv4:       ${LOCAL_WG_IP}"
    [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]] && \
    echo "  隧道 IPv6:       ${LOCAL_WG_IP6}"
    echo "  监听端口:        ${WG_PORT}"
    echo "  物理接口:        ${PHYSICAL_INTERFACE}"
    echo "  对端:             ${EFFECTIVE_ENDPOINT}"
    [[ "$ROLE" == "source" ]] && \
    echo "  策略路由:        fwmark=${FWMARK} -> table ${ROUTE_TABLE}"
    echo ""
    echo "------------------------------------------------------------"
    echo -e "  ${YELLOW}本机公钥 (复制给对端):${NC}"
    echo "  ${PUBLIC_KEY}"
    echo "------------------------------------------------------------"

    if [[ "$PEER_PUBLIC_KEY" == "PEER_PUBLIC_KEY_PLACEHOLDER" ]]; then
        echo -e "  ${RED}注意:  对端公钥未配置!${NC}"
        echo "  编辑:  vim ${WG_DIR}/${WG_INTERFACE}.conf"
        echo "  重启:  systemctl restart wg-quick@${WG_INTERFACE}"
    fi

    echo ""
    echo "  常用命令:"
    echo "    wg show"
    echo "    systemctl restart wg-quick@${WG_INTERFACE}"
    echo "    journalctl -u wg-quick@${WG_INTERFACE} -f"
    echo "============================================================"
}

# ==================== 卸载 ====================
uninstall_wireguard() {
    log_warn "准备卸载 WireGuard 配置..."

    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        read -p "确定要卸载?  [y/N]:  " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0
    fi

    wg-quick down "${WG_INTERFACE}" 2>/dev/null || true
    systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
    
    # 清理路由规则
    ip rule del fwmark 255 table 100 2>/dev/null || true
    ip -6 rule del fwmark 255 table 100 2>/dev/null || true
    ip route del default table 100 2>/dev/null || true
    ip -6 route del default table 100 2>/dev/null || true
    
    rm -f "${WG_DIR}/${WG_INTERFACE}.conf"

    log_info "卸载完成"
    exit 0
}

# ==================== 显示当前配置 ====================
show_current_config() {
    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"
    if [[ -f "$config_file" ]]; then
        echo "配置文件:  $config_file"
        echo "------------------------------------------------------------"
        cat "$config_file"
        echo "------------------------------------------------------------"
        echo ""
        echo "路由规则 (IPv4):"
        ip rule list | grep -E "fwmark|table" || echo "  无"
        echo ""
        echo "路由规则 (IPv6):"
        ip -6 rule list | grep -E "fwmark|table" || echo "  无"
        echo ""
        wg show 2>/dev/null || echo "WireGuard 未运行"
    else
        log_warn "配置文件不存在"
    fi
    exit 0
}

# ==================== 仅生成密钥 ====================
gen_key_only() {
    mkdir -p "$WG_DIR"
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

    echo ""
    echo "私钥:  ${PRIVATE_KEY}"
    echo "公钥: ${PUBLIC_KEY}"
    echo ""

    read -p "保存到文件? [y/N]: " save
    if [[ "$save" =~ ^[Yy]$ ]]; then
        read -p "文件名前缀 [wg]:  " prefix
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
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行"
        exit 1
    fi

    parse_args "$@"

    [[ "$GEN_KEY_ONLY" == "true" ]] && gen_key_only
    [[ "$SHOW_CONFIG" == "true" ]] && show_current_config
    [[ "$UNINSTALL" == "true" ]] && uninstall_wireguard

    detect_ipv6_support

    if [[ -z "$ROLE" ]] || [[ -z "$LOCAL_WG_IP" ]] || [[ -z "$PHYSICAL_INTERFACE" ]] || \
       { [[ -z "$PEER_ENDPOINT" ]] && [[ -z "$PEER_ENDPOINT6" ]]; }; then
        interactive_input
    fi

    validate_params

    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        echo ""
        echo "配置:  $ROLE | $LOCAL_WG_IP | $PHYSICAL_INTERFACE | ${PEER_ENDPOINT:-$PEER_ENDPOINT6}"
        read -p "继续? [Y/n]: " confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
    fi

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

main "$@"
