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
  -r, --role <server|client>    角色
                                  server: 服务端 (出口端，监听并接收客户端连接，NAT 转发)
                                  client: 客户端 (如香港代理节点，主动连接到 server)
  -l, --local-ip <IP/MASK>      本机隧道IPv4 (如: 10.200.200.1/24)
  -i, --interface <NAME>        物理网卡接口名 (如: eth0, enp1s0)
  -e, --endpoint <IP>           服务端公网IP (仅 client，IPv4或IPv6)

IPv6 参数:
  -6, --local-ip6 <IP/MASK>     本机隧道IPv6 (如: fd00:200::1/64)
  -E, --endpoint6 <IP>          服务端公网IPv6 (仅 client)
  -N, --client-net6 <CIDR>      客户端隧道IPv6网段 (仅 server)
      --ipv6 <auto|yes|no>      IPv6模式 (默认: auto)

可选参数:
  -k, --peer-key <KEY>          对端WireGuard公钥 (可稍后填写)
  -p, --port <PORT>             本机监听端口 (server 默认: 51820)
                                  client 不指定时不写 ListenPort，由内核分配随机
                                  端口，同一台机器上多个 client 接口不会撞端口
  -P, --peer-port <PORT>        对端端口 (仅 client, 默认: 同 --port 或 51820)
  -w, --wg-interface <NAME>     WireGuard接口名 (默认: wg0)
  -m, --fwmark <MARK>           策略路由fwmark值 (仅 client, 默认: 255)
  -t, --table <ID>              策略路由表ID (仅 client, 默认: 100)
  -n, --client-net <CIDR>       客户端隧道IPv4网段 (仅 server)
  -a, --allowed-ips <CIDR>      对端AllowedIPs (自动生成)
      --keepalive <SEC>         PersistentKeepalive (默认: 25)
      --show-config             显示当前配置并退出
      --add-peer                向已有服务端添加新客户端 (仅 server)
      --uninstall               卸载WireGuard配置 (只影响 -w 指定的接口)
  -y, --yes                     跳过确认提示
  -h, --help                    显示此帮助信息

独立命令 (先换密钥，再互填公钥，避免"先有鸡还是先有蛋"):
      --gen-key                 生成该接口的密钥对并打印公钥；已存在则直接复用
                                  (幂等；要轮换密钥请先删除密钥文件)
      --show-pubkey             只打印该接口的公钥到 stdout，供脚本取值
      --gen-key-only            --gen-key 的旧名，保留兼容

  密钥文件按接口名存放: /etc/wireguard/<接口名>_private.key / _public.key
  (wg0 若已存在旧版按角色命名的 client_*.key / server_*.key 则继续沿用)

架构说明:
  server (服务端) 作为 WireGuard Server 监听连接 (隧道 IP: x.x.x.1)，
  多个 client (客户端) 主动连接到 server。
  适用于多个香港代理节点共用同一个出口节点的场景:
    [HK-1 client .2] ──┐
    [HK-2 client .3] ──┼── WireGuard ──> [server .1 出口] ──> 互联网
    [HK-3 client .4] ──┘

  反过来，同一台机器也可以起多个 client 接口，按 fwmark 分流到不同出口:
    ss :8081 → fwmark 255 → table 100 → wg0 → [出口 A]
    ss :8082 → fwmark 254 → table 101 → wg1 → [出口 B]
  每个接口用独立的 -w / -m / -t，密钥按接口名自动隔离。

示例:
  # 服务端 (出口端，监听等待客户端连接，隧道 IP 为 .1)
  ./wireguard-tunnel-setup.sh -r server -l 10.200.200.1/24 -i enp1s0

  # 客户端 (香港代理节点，连接到服务端)
  ./wireguard-tunnel-setup.sh -r client -l 10.200.200.2/24 -i eth0 -e 45.77.47.173

  # 客户端 IPv4+IPv6 双栈
  ./wireguard-tunnel-setup.sh -r client -l 10.200.200.2/24 -6 fd00:200::2/64 \
    -i eth0 -e 45.77.47.173 -E 2001:db8::2

  # 同机第二个客户端 (独立接口/fwmark/路由表，连到另一个出口)
  ./wireguard-tunnel-setup.sh -r client -w wg1 -l 10.200.201.2/24 \
    -i eth0 -e 45.76.176.94 -m 254 -t 101

  # 向服务端添加新客户端
  ./wireguard-tunnel-setup.sh --add-peer -k <客户端公钥> -a 10.200.200.3/32

  # 先换公钥再部署 (两端都不需要事先知道对方)
  A: ./wireguard-tunnel-setup.sh --gen-key -w wg1        # 打印 A 的公钥
  B: ./wireguard-tunnel-setup.sh -r server ... -k <A的公钥>
  B: ./wireguard-tunnel-setup.sh --show-pubkey           # 取 B 的公钥
  A: ./wireguard-tunnel-setup.sh -r client -w wg1 ... -k <B的公钥>

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
            -p|--port)           WG_PORT="$2"; WG_PORT_SET=true; shift 2 ;;
            -P|--peer-port)      PEER_PORT="$2"; shift 2 ;;
            -w|--wg-interface)   WG_INTERFACE="$2"; shift 2 ;;
            -m|--fwmark)         FWMARK="$2"; shift 2 ;;
            -t|--table)          ROUTE_TABLE="$2"; shift 2 ;;
            -n|--client-net)     CLIENT_NETWORK="$2"; shift 2 ;;
            -N|--client-net6)    CLIENT_NETWORK6="$2"; shift 2 ;;
            -a|--allowed-ips)    ALLOWED_IPS="$2"; shift 2 ;;
            --ipv6)              ENABLE_IPV6="$2"; shift 2 ;;
            --keepalive)         KEEPALIVE="$2"; shift 2 ;;
            --gen-key|--gen-key-only) GEN_KEY=true; shift ;;
            --show-pubkey)       SHOW_PUBKEY=true; shift ;;
            --show-config)       SHOW_CONFIG=true; shift ;;
            --add-peer)          ADD_PEER=true; shift ;;
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
        echo "  1) server - 服务端 (出口端，监听并接收客户端连接，NAT 转发)"
        echo "  2) client - 客户端 (如香港代理节点，连接到服务端)"
        read -p "请输入 [1/2]: " role_choice
        case $role_choice in
            1|server) ROLE="server" ;;
            2|client) ROLE="client" ;;
            *) log_error "无效选择"; exit 1 ;;
        esac
    fi

    if [[ -z "$LOCAL_WG_IP" ]]; then
        if [[ "$ROLE" == "server" ]]; then
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
            if [[ "$ROLE" == "server" ]]; then
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

    if [[ "$ROLE" == "client" ]]; then
        if [[ -z "$PEER_ENDPOINT" ]]; then
            read -p "服务端公网 IPv4: " PEER_ENDPOINT
        fi

        if [[ "$HAS_IPV6" == "true" ]] && [[ -z "$PEER_ENDPOINT6" ]]; then
            read -p "服务端公网 IPv6 (可选): " PEER_ENDPOINT6
        fi
    fi

    if [[ -z "$PEER_PUBLIC_KEY" ]]; then
        if [[ "$ROLE" == "client" ]]; then
            read -p "服务端WireGuard公钥 (可留空): " PEER_PUBLIC_KEY
        else
            read -p "首个客户端WireGuard公钥 (可留空，稍后用 --add-peer 添加): " PEER_PUBLIC_KEY
        fi
        PEER_PUBLIC_KEY="${PEER_PUBLIC_KEY:-PEER_PUBLIC_KEY_PLACEHOLDER}"
    fi

    if [[ "$ROLE" == "client" ]]; then
        if [[ -z "$FWMARK" ]]; then
            read -p "策略路由 fwmark 值 [默认: 255]:  " FWMARK
            FWMARK="${FWMARK:-255}"
        fi
        if [[ -z "$ROUTE_TABLE" ]]; then
            read -p "策略路由表 ID [默认: 100]: " ROUTE_TABLE
            ROUTE_TABLE="${ROUTE_TABLE:-100}"
        fi
    fi

    if [[ "$ROLE" == "server" ]]; then
        if [[ -z "$CLIENT_NETWORK" ]]; then
            default_net=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.0\//')
            read -p "客户端隧道 IPv4 网段 [默认: $default_net]: " CLIENT_NETWORK
            CLIENT_NETWORK="${CLIENT_NETWORK:-$default_net}"
        fi
        if [[ "$HAS_IPV6" == "true" ]] && [[ -z "$CLIENT_NETWORK6" ]]; then
            read -p "客户端隧道 IPv6 网段 [默认: fd00:200::/64]: " CLIENT_NETWORK6
            CLIENT_NETWORK6="${CLIENT_NETWORK6:-fd00:200::/64}"
        fi
    fi

    if [[ "$ROLE" == "client" ]]; then
        # client 默认不监听固定端口，避免同机多个接口抢同一个 UDP 端口
        if [[ -z "$PEER_PORT" ]]; then
            read -p "对端 WireGuard 端口 [默认: $WG_PORT]: " input_port
            PEER_PORT="${input_port:-$WG_PORT}"
        fi
    else
        read -p "WireGuard 监听端口 [默认: $WG_PORT]: " input_port
        if [[ -n "$input_port" ]]; then
            WG_PORT="$input_port"
            WG_PORT_SET=true
        fi
    fi
}

# ==================== 验证参数 ====================
validate_params() {
    local errors=0

    if [[ -z "$ROLE" ]] || [[ !  "$ROLE" =~ ^(server|client)$ ]]; then
        log_error "必须指定有效的角色:  server 或 client"
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

    if [[ "$ROLE" == "client" ]] && [[ -z "$PEER_ENDPOINT" ]] && [[ -z "$PEER_ENDPOINT6" ]]; then
        log_error "客户端必须指定服务端 IP (-e 或 -E)"
        errors=$((errors + 1))
    fi

    if [[ "$ROLE" == "client" ]]; then
        FWMARK="${FWMARK:-255}"
        ROUTE_TABLE="${ROUTE_TABLE:-100}"
    fi

    # 对端端口独立于本机监听端口: 同机多个 client 接口各自随机监听，
    # 但仍要连到对端真实的 ListenPort。未指定时沿用 --port 保持旧行为。
    PEER_PORT="${PEER_PORT:-$WG_PORT}"

    # 对端公钥缺失时不写 [Peer]，让接口能先起来，补齐公钥后重跑即可
    if [[ -z "$PEER_PUBLIC_KEY" ]] || [[ "$PEER_PUBLIC_KEY" == "PEER_PUBLIC_KEY_PLACEHOLDER" ]]; then
        PEER_KEY_MISSING=true
    fi

    if [[ "$ROLE" == "server" ]]; then
        if [[ -z "$CLIENT_NETWORK" ]]; then
            CLIENT_NETWORK=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.0\//')
            log_info "自动推断客户端 IPv4 网段:  $CLIENT_NETWORK"
        fi
        if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]] && [[ -z "$CLIENT_NETWORK6" ]]; then
            CLIENT_NETWORK6="fd00:200::/64"
            log_info "使用默认客户端 IPv6 网段:  $CLIENT_NETWORK6"
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

    if [[ "$ROLE" == "client" ]]; then
        ips="0.0.0.0/0"
        if [[ "$HAS_IPV6" == "true" ]]; then
            ips="${ips}, ::/0"
        fi
    else
        # server: AllowedIPs 为客户端隧道 IP
        local peer_ip4
        peer_ip4=$(echo "$LOCAL_WG_IP" | sed 's/\.[0-9]*\//.2\//' | sed 's/\/[0-9]*/\/32/')
        ips="$peer_ip4"

        if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]]; then
            local peer_ip6
            peer_ip6=$(echo "$LOCAL_WG_IP6" | sed 's/::[0-9a-fA-F]*\/[0-9]*/::2\/128/')
            ips="${ips}, ${peer_ip6}"
        fi
    fi

    ALLOWED_IPS="${ALLOWED_IPS:-$ips}"
}

# ==================== 确定 Endpoint ====================
get_endpoint() {
    local port="${PEER_PORT:-$WG_PORT}"
    if [[ -n "$PEER_ENDPOINT" ]]; then
        EFFECTIVE_ENDPOINT="${PEER_ENDPOINT}:${port}"
    elif [[ -n "$PEER_ENDPOINT6" ]]; then
        EFFECTIVE_ENDPOINT="[${PEER_ENDPOINT6}]:${port}"
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

# ==================== 解析密钥文件路径 ====================
# 密钥按接口名存放 (wg1_private.key)，这样同一台机器上多个 client 接口
# 各自持有独立身份。旧版本按角色命名 (client_*.key / server_*.key)，会让
# 第二个 client 静默复用第一个的密钥对，因此新接口一律用接口名。
# wg0 若只有旧的角色命名密钥则继续沿用，避免升级脚本后现有隧道换密钥断连。
resolve_key_files() {
    PRIVATE_KEY_FILE="${WG_DIR}/${WG_INTERFACE}_private.key"
    PUBLIC_KEY_FILE="${WG_DIR}/${WG_INTERFACE}_public.key"

    [[ -f "$PRIVATE_KEY_FILE" ]] && return 0
    [[ "$WG_INTERFACE" != "wg0" ]] && return 0

    local legacy
    for legacy in $ROLE client server; do
        if [[ -f "${WG_DIR}/${legacy}_private.key" ]] && [[ -f "${WG_DIR}/${legacy}_public.key" ]]; then
            PRIVATE_KEY_FILE="${WG_DIR}/${legacy}_private.key"
            PUBLIC_KEY_FILE="${WG_DIR}/${legacy}_public.key"
            return 0
        fi
    done
}

# ==================== 生成密钥 ====================
generate_keys() {
    log_step "准备 WireGuard 密钥对..."

    mkdir -p "$WG_DIR"
    resolve_key_files

    if [[ -f "$PRIVATE_KEY_FILE" ]] && [[ -f "$PUBLIC_KEY_FILE" ]]; then
        if [[ "$AUTO_CONFIRM" != "true" ]]; then
            read -p "密钥已存在 (${PRIVATE_KEY_FILE})，是否重新生成? [y/N]: " regen
            if [[ ! "$regen" =~ ^[Yy]$ ]]; then
                log_info "复用现有密钥: $PRIVATE_KEY_FILE"
                PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
                PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")
                return 0
            fi
            # 重新生成时写按接口名命名的新文件，不覆盖旧的角色命名密钥
            PRIVATE_KEY_FILE="${WG_DIR}/${WG_INTERFACE}_private.key"
            PUBLIC_KEY_FILE="${WG_DIR}/${WG_INTERFACE}_public.key"
        else
            log_info "复用现有密钥: $PRIVATE_KEY_FILE"
            PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
            PUBLIC_KEY=$(cat "$PUBLIC_KEY_FILE")
            return 0
        fi
    fi

    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

    # umask 见 gen_key(): 避免私钥文件先以 644 落盘再补 chmod
    ( umask 077; echo "$PRIVATE_KEY" > "$PRIVATE_KEY_FILE" )
    echo "$PUBLIC_KEY" > "$PUBLIC_KEY_FILE"

    log_info "密钥已生成: $PRIVATE_KEY_FILE"
}

# ==================== 生成客户端配置 ====================
generate_client_config() {
    log_step "生成客户端 WireGuard 配置..."

    build_address_list
    build_allowed_ips
    get_endpoint

    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"

    cat > "$config_file" << EOF
# ============================================================
# WireGuard 客户端配置 - IPv4/IPv6 双栈
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 角色: 将 fwmark=${FWMARK} 的流量通过隧道转发到服务端
# ============================================================

[Interface]
Address = ${ADDRESS_LIST}
PrivateKey = ${PRIVATE_KEY}
Table = off
EOF

    # 只在显式指定 -p 时固定监听端口。client 主动发起连接，不需要固定端口，
    # 而写死同一个端口会让同机第二个接口 wg-quick up 时 EADDRINUSE 失败。
    if [[ "$WG_PORT_SET" == "true" ]]; then
        echo "ListenPort = ${WG_PORT}" >> "$config_file"
    fi

    cat >> "$config_file" << EOF

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

    # 缺对端公钥时把 [Peer] 注释掉: 写空 PublicKey 会让 wg setconf 直接报错，
    # 整个 wg-quick up 失败。注释掉则接口能起来，补公钥后重跑脚本即可。
    if [[ "$PEER_KEY_MISSING" == "true" ]]; then
        cat >> "$config_file" << EOF

# [Peer] 对端公钥未提供 —— 拿到公钥后重跑本脚本并加上 -k <对端公钥>
#[Peer]
#PublicKey = <对端公钥>
#Endpoint = ${EFFECTIVE_ENDPOINT}
#AllowedIPs = ${ALLOWED_IPS}
#PersistentKeepalive = ${KEEPALIVE}
EOF
    else
        cat >> "$config_file" << EOF

[Peer]
PublicKey = ${PEER_PUBLIC_KEY}
Endpoint = ${EFFECTIVE_ENDPOINT}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${KEEPALIVE}
EOF
    fi

    chmod 600 "$config_file"
    log_info "配置文件已生成:  $config_file"
}

# ==================== 生成服务端配置 ====================
generate_server_config() {
    log_step "生成服务端 WireGuard 配置..."

    build_address_list
    build_allowed_ips

    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"

    cat > "$config_file" << EOF
# ============================================================
# WireGuard 服务端配置 - IPv4/IPv6 双栈
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 角色: 接收多个客户端隧道流量并 NAT 转发到互联网
# ============================================================

[Interface]
Address = ${ADDRESS_LIST}
ListenPort = ${WG_PORT}
PrivateKey = ${PRIVATE_KEY}

# === IPv4 NAT 和转发 ===
PostUp = iptables -t nat -D POSTROUTING -s ${CLIENT_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostUp = iptables -t nat -A POSTROUTING -s ${CLIENT_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE
PostUp = iptables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT
PostUp = iptables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
PostUp = iptables -A FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$CLIENT_NETWORK6" ]]; then
        cat >> "$config_file" << EOF

# === IPv6 NAT 和转发 ===
PostUp = ip6tables -t nat -D POSTROUTING -s ${CLIENT_NETWORK6} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostUp = ip6tables -t nat -A POSTROUTING -s ${CLIENT_NETWORK6} -o ${PHYSICAL_INTERFACE} -j MASQUERADE
PostUp = ip6tables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostUp = ip6tables -A FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT
PostUp = ip6tables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
PostUp = ip6tables -A FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF
    fi

    cat >> "$config_file" << EOF

# === 关闭时清理 ===
PostDown = iptables -t nat -D POSTROUTING -s ${CLIENT_NETWORK} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostDown = iptables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
EOF

    if [[ "$HAS_IPV6" == "true" ]] && [[ -n "$CLIENT_NETWORK6" ]]; then
        cat >> "$config_file" << EOF
PostDown = ip6tables -t nat -D POSTROUTING -s ${CLIENT_NETWORK6} -o ${PHYSICAL_INTERFACE} -j MASQUERADE 2>/dev/null || true
PostDown = ip6tables -D FORWARD -i ${WG_INTERFACE} -o ${PHYSICAL_INTERFACE} -j ACCEPT 2>/dev/null || true
PostDown = ip6tables -D FORWARD -i ${PHYSICAL_INTERFACE} -o ${WG_INTERFACE} -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
EOF
    fi

    # 无客户端公钥时不写 [Peer]，接口照样能起来监听，之后用 --add-peer 补
    if [[ "$PEER_KEY_MISSING" == "true" ]]; then
        cat >> "$config_file" << EOF

# 暂无客户端。添加方式:
#   $0 --add-peer -w ${WG_INTERFACE} -k <客户端公钥> -a ${ALLOWED_IPS}
EOF
    else
        cat >> "$config_file" << EOF

[Peer]
# 客户端 (可通过 --add-peer 添加更多客户端)
PublicKey = ${PEER_PUBLIC_KEY}
AllowedIPs = ${ALLOWED_IPS}
PersistentKeepalive = ${KEEPALIVE}
EOF
    fi

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

    # 只有真正监听固定端口的接口才需要放行入站。client 不指定 -p 时用随机
    # 端口主动发起连接，开一个固定端口既没用又多暴露一个面。
    local needs_inbound=false
    if [[ "$ROLE" == "server" ]] || [[ "$WG_PORT_SET" == "true" ]]; then
        needs_inbound=true
    fi

    # ufw 环境必须用 ufw 添加规则: 裸 iptables 规则在 ufw reload/重启后会被清空，
    # 导致 WireGuard 握手包被默认 DROP 策略丢弃、隧道静默中断
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        if [[ "$needs_inbound" == "true" ]]; then
            ufw allow "${WG_PORT}/udp" >/dev/null
            log_info "ufw 已放行 UDP 端口 ${WG_PORT}"
        fi
        if [[ "$ROLE" == "server" ]]; then
            ufw route allow in on "${WG_INTERFACE}" out on "${PHYSICAL_INTERFACE}" >/dev/null
            log_info "ufw 已放行 ${WG_INTERFACE} -> ${PHYSICAL_INTERFACE} 转发"
        fi
        return 0
    fi

    [[ "$needs_inbound" != "true" ]] && return 0

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

# ==================== 保护策略路由不被 networkd 清除 ====================
# client 依赖 wg-quick PostUp 手工加的策略规则/路由 (fwmark -> table，endpoint 旁路，
# table 默认经 wg0)。systemd-networkd 默认 ManageForeign*=yes，会在每次 DHCP 续租/
# 重配网卡时把这些"外来"规则/路由删掉，导致隧道在但不转发，必须重启 wg-quick 才恢复。
# 关掉 networkd 对外来规则/路由的管理即可根治。
configure_networkd_persistence() {
    [[ "$ROLE" != "client" ]] && return 0
    command -v systemctl &>/dev/null || return 0
    systemctl is-active --quiet systemd-networkd 2>/dev/null || return 0

    log_step "保护策略路由不被 systemd-networkd 清除..."

    local dropin_dir="/etc/systemd/networkd.conf.d"
    local dropin="${dropin_dir}/10-keep-wg-routes.conf"
    mkdir -p "$dropin_dir"
    local desired
    desired=$(cat << 'EOF'
# 阻止 systemd-networkd 删除 wg-quick 通过 PostUp 添加的策略路由规则/路由。
# 默认 ManageForeign*=yes 会在 DHCP 续租/重配网卡时清掉它们，使客户端隧道在但不转发。
[Network]
ManageForeignRoutes=no
ManageForeignRoutingPolicyRules=no
EOF
)

    # 已经配好就别动: 在跑生产流量的节点上追加第二条隧道时，无谓地重启
    # networkd 会让物理网卡重跑 DHCP，把现有隧道也一起抖一下。
    # 只比对生效的配置项，注释文案不同不算差异。
    if [[ -f "$dropin" ]] \
       && grep -q '^ManageForeignRoutes=no' "$dropin" \
       && grep -q '^ManageForeignRoutingPolicyRules=no' "$dropin"; then
        log_info "networkd 保护已就位，跳过重启: ${dropin}"
        return 0
    fi

    echo "$desired" > "$dropin"
    systemctl restart systemd-networkd 2>/dev/null || true
    log_info "已写入 ${dropin} 并重启 networkd"
}

# ==================== 启动服务 ====================
start_wireguard() {
    # client 缺对端公钥时不要启动: 策略路由会把 fwmark 流量指向一个没有 peer
    # 的接口，等于黑洞。不启动则该 fwmark 继续走原来的路径，不影响现网。
    if [[ "$ROLE" == "client" ]] && [[ "$PEER_KEY_MISSING" == "true" ]]; then
        log_warn "对端公钥未配置，跳过启动 ${WG_INTERFACE} (避免黑洞 fwmark ${FWMARK} 的流量)"
        systemctl enable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true
        return 0
    fi

    log_step "启动 WireGuard 服务..."

    wg-quick down "${WG_INTERFACE}" 2>/dev/null || true

    # 清理可能残留的路由规则
    if [[ "$ROLE" == "client" ]]; then
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
    local role_desc
    if [[ "$ROLE" == "client" ]]; then
        role_desc="客户端 (client)"
    else
        role_desc="服务端 (server)"
    fi

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}配置完成! ${NC}"
    echo "============================================================"
    echo ""
    echo "  角色:             ${role_desc}"
    echo "  WireGuard接口:   ${WG_INTERFACE}"
    echo "  隧道 IPv4:       ${LOCAL_WG_IP}"
    [[ "$HAS_IPV6" == "true" ]] && [[ -n "$LOCAL_WG_IP6" ]] && \
    echo "  隧道 IPv6:       ${LOCAL_WG_IP6}"
    if [[ "$ROLE" == "server" ]] || [[ "$WG_PORT_SET" == "true" ]]; then
        echo "  监听端口:        ${WG_PORT}"
    else
        echo "  监听端口:        (随机，由内核分配)"
    fi
    echo "  物理接口:        ${PHYSICAL_INTERFACE}"
    echo "  对端:             ${EFFECTIVE_ENDPOINT:-(监听模式)}"
    [[ "$ROLE" == "client" ]] && \
    echo "  策略路由:        fwmark=${FWMARK} -> table ${ROUTE_TABLE}"
    echo "  密钥文件:        ${PRIVATE_KEY_FILE}"
    echo ""
    echo "------------------------------------------------------------"
    echo -e "  ${YELLOW}本机公钥 (复制给对端):${NC}"
    echo "  ${PUBLIC_KEY}"
    echo "------------------------------------------------------------"

    if [[ "$PEER_KEY_MISSING" == "true" ]]; then
        echo ""
        echo -e "  ${RED}注意: 对端公钥未配置，[Peer] 段未写入${NC}"
        echo "  拿到对端公钥后重跑本脚本，加上 -k <对端公钥> 即可 (密钥会自动复用)"
        [[ "$ROLE" == "client" ]] && \
        echo "  接口暂未启动，以免把 fwmark ${FWMARK} 的流量导进黑洞"
    fi

    if [[ "$ROLE" == "server" ]]; then
        echo ""
        echo "  添加更多客户端:"
        echo "    $0 --add-peer -k <客户端公钥> -a <客户端隧道IP/32>"
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
    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"

    log_warn "准备卸载 WireGuard 配置: ${WG_INTERFACE}"

    if [[ "$AUTO_CONFIRM" != "true" ]]; then
        read -p "确定要卸载 ${WG_INTERFACE}? [y/N]: " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0
    fi

    wg-quick down "${WG_INTERFACE}" 2>/dev/null || true
    systemctl disable "wg-quick@${WG_INTERFACE}" 2>/dev/null || true

    # 从该接口自己的配置里解析 fwmark/table。曾经这里硬编码 255/100，卸载
    # 任意接口都会删掉 wg0 的策略路由，把同机其他隧道一起打断。
    local mark="$FWMARK" table="$ROUTE_TABLE" parsed
    if [[ -f "$config_file" ]]; then
        parsed=$(sed -n 's/^PostUp = ip rule add fwmark \([0-9]*\) table \([0-9]*\).*/\1 \2/p' "$config_file" | head -1)
        if [[ -n "$parsed" ]]; then
            mark="${mark:-${parsed% *}}"
            table="${table:-${parsed#* }}"
        fi
    fi

    if [[ -n "$mark" ]] && [[ -n "$table" ]]; then
        ip rule del fwmark "$mark" table "$table" 2>/dev/null || true
        ip -6 rule del fwmark "$mark" table "$table" 2>/dev/null || true
        ip route del default table "$table" 2>/dev/null || true
        ip -6 route del default table "$table" 2>/dev/null || true
        log_info "已清理策略路由: fwmark ${mark} -> table ${table}"
    else
        log_warn "无法确定 ${WG_INTERFACE} 的 fwmark/table，跳过策略路由清理"
        log_warn "如有残留请手动指定: $0 --uninstall -w ${WG_INTERFACE} -m <mark> -t <table>"
    fi

    # 清理 endpoint 旁路规则 (同样只删该配置里记录的那条)
    if [[ -f "$config_file" ]]; then
        local ep
        while read -r ep; do
            [[ -n "$ep" ]] && ip rule del to "$ep" lookup main 2>/dev/null || true
        done < <(sed -n 's|^PostUp = ip rule add to \([0-9./]*\) lookup main.*|\1|p' "$config_file")
        while read -r ep; do
            [[ -n "$ep" ]] && ip -6 rule del to "$ep" lookup main 2>/dev/null || true
        done < <(sed -n 's|^PostUp = ip -6 rule add to \([0-9a-fA-F:/]*\) lookup main.*|\1|p' "$config_file")
    fi

    rm -f "$config_file"

    log_info "卸载完成: ${WG_INTERFACE} (密钥文件保留在 ${WG_DIR})"
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

# ==================== 生成密钥 (独立命令) ====================
# 幂等: 已有密钥就直接打印公钥，不重新生成。这样可以在两端都还不知道
# 对方公钥时先各自建号，再互填 -k，绕开"先有鸡还是先有蛋"。
gen_key() {
    install_wireguard
    mkdir -p "$WG_DIR"
    resolve_key_files

    if [[ -f "$PRIVATE_KEY_FILE" ]] && [[ -f "$PUBLIC_KEY_FILE" ]]; then
        log_info "密钥已存在，直接复用 (要轮换请先删除该文件)"
    else
        # 先收紧 umask 再重定向: 否则文件按默认 umask 建成 644，私钥会有一段
        # world-readable 的窗口，之后 chmod 才补上
        ( umask 077; wg genkey > "$PRIVATE_KEY_FILE" )
        wg pubkey < "$PRIVATE_KEY_FILE" > "$PUBLIC_KEY_FILE"
        log_info "密钥已生成"
    fi

    echo ""
    echo "  接口:   ${WG_INTERFACE}"
    echo "  私钥:   ${PRIVATE_KEY_FILE}"
    echo "  公钥:   ${PUBLIC_KEY_FILE}"
    echo ""
    echo "------------------------------------------------------------"
    echo -e "  ${YELLOW}公钥 (复制给对端，作为对端的 -k 参数):${NC}"
    echo "  $(cat "$PUBLIC_KEY_FILE")"
    echo "------------------------------------------------------------"
    echo ""
    exit 0
}

# ==================== 仅打印公钥 (供脚本取值) ====================
show_pubkey() {
    resolve_key_files

    if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
        echo "[ERROR] 公钥不存在: ${PUBLIC_KEY_FILE}" >&2
        echo "        请先运行: $0 --gen-key -w ${WG_INTERFACE}" >&2
        exit 1
    fi

    cat "$PUBLIC_KEY_FILE"
    exit 0
}

# ==================== 添加客户端到服务端 ====================
add_peer() {
    local config_file="${WG_DIR}/${WG_INTERFACE}.conf"

    if [[ ! -f "$config_file" ]]; then
        log_error "配置文件不存在: $config_file"
        log_error "请先使用 -r server 初始化服务端"
        exit 1
    fi

    local peer_key="${PEER_PUBLIC_KEY:-}"
    local peer_ips="${ALLOWED_IPS:-}"

    if [[ -z "$peer_key" ]] || [[ "$peer_key" == "PEER_PUBLIC_KEY_PLACEHOLDER" ]]; then
        read -rp "客户端 WireGuard 公钥: " peer_key
        if [[ -z "$peer_key" ]]; then
            log_error "公钥不能为空"
            exit 1
        fi
    fi

    if [[ -z "$peer_ips" ]]; then
        read -rp "客户端隧道 IP (如 10.200.200.3/32): " peer_ips
        if [[ -z "$peer_ips" ]]; then
            log_error "隧道 IP 不能为空"
            exit 1
        fi
    fi

    log_step "添加客户端到 $config_file ..."

    cat >> "$config_file" << EOF

[Peer]
# 客户端 - 添加于 $(date '+%Y-%m-%d %H:%M:%S')
PublicKey = ${peer_key}
AllowedIPs = ${peer_ips}
PersistentKeepalive = ${KEEPALIVE}
EOF

    # 热加载配置
    if wg show "$WG_INTERFACE" &>/dev/null; then
        wg syncconf "$WG_INTERFACE" <(wg-quick strip "$WG_INTERFACE")
        log_info "配置已热加载"
    else
        log_warn "WireGuard 未运行，配置将在下次启动时生效"
    fi

    echo ""
    log_info "客户端已添加"
    echo "  公钥:       $peer_key"
    echo "  AllowedIPs: $peer_ips"
}

# ==================== 主函数 ====================
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行"
        exit 1
    fi

    parse_args "$@"

    [[ "$SHOW_PUBKEY" == "true" ]] && show_pubkey
    [[ "$GEN_KEY" == "true" ]] && gen_key
    [[ "$SHOW_CONFIG" == "true" ]] && show_current_config
    [[ "$UNINSTALL" == "true" ]] && uninstall_wireguard
    [[ "$ADD_PEER" == "true" ]] && { add_peer; exit 0; }

    detect_ipv6_support

    local need_interactive=false
    if [[ -z "$ROLE" ]] || [[ -z "$LOCAL_WG_IP" ]] || [[ -z "$PHYSICAL_INTERFACE" ]]; then
        need_interactive=true
    fi
    if [[ "$ROLE" == "client" ]] && [[ -z "$PEER_ENDPOINT" ]] && [[ -z "$PEER_ENDPOINT6" ]]; then
        need_interactive=true
    fi
    if [[ "$need_interactive" == "true" ]]; then
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

    if [[ "$ROLE" == "client" ]]; then
        generate_client_config
    else
        generate_server_config
    fi

    configure_system
    configure_networkd_persistence
    start_wireguard
    show_summary
}

main "$@"
