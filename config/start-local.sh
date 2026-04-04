#!/bin/bash
# ============================================================
# Shadowsocks-rust 本地代理快速启动脚本
# 启动本地 SOCKS5 / HTTP 代理，支持 Linux (systemd) 和 macOS (launchctl)
#
# 使用方式:
#   交互模式:  ./start-local.sh
#   参数模式:  ./start-local.sh -s <服务器> -p <端口> -k <密码> [-m <加密方式>]
#
# 示例:
#   ./start-local.sh -s 1.2.3.4 -p 8388 -k "my_password"
#   ./start-local.sh -s example.com -p 8388 -k "pass" --socks-port 1080 --http-port 1081
# ============================================================

set -e

# ==================== 默认配置 ====================
SERVER_ADDR=""
SERVER_PORT="8388"
SS_PASSWORD=""
SS_METHOD="aes-256-gcm"

SOCKS_PORT="1080"
HTTP_PORT="1081"
LOG_LEVEL="info"

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RUN_DIR="$PROJECT_DIR/.run"

# ==================== 平台检测 ====================
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"

INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="sslocal"

if [[ "$OS_TYPE" == "Darwin" ]]; then
    PLATFORM="macos"
    CONFIG_DIR="/usr/local/etc/sslocal"
    LOG_DIR="/usr/local/var/log/sslocal"
    PLIST_LABEL="com.shadowsocks.sslocal"
    PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
else
    PLATFORM="linux"
    CONFIG_DIR="/etc/sslocal"
    LOG_DIR="/var/log/sslocal"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
fi

# 自动选择二进制文件
detect_sslocal() {
    local bin=""
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        # macOS: 根据 CPU 架构选择对应二进制
        if [[ "$ARCH_TYPE" == "arm64" ]]; then
            bin="$PROJECT_DIR/bin/aarch64-musl/sslocal"
        else
            bin="$PROJECT_DIR/bin/x86_64-gnu/sslocal"
        fi
    else
        # Linux: 使用项目自带的二进制
        bin="$PROJECT_DIR/bin/x86_64-gnu/sslocal"
    fi
    echo "$bin"
}

SSLOCAL="$(detect_sslocal)"

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
Shadowsocks-rust 本地代理快速启动脚本

用法: ./start-local.sh [选项]

选项:
  -s, --server <ADDR>       远程服务器地址 (必填，或交互输入)
  -p, --port <PORT>         远程服务器端口 (默认: 8388)
  -k, --password <PASS>     连接密码 (必填，或交互输入)
  -m, --method <METHOD>     加密方式 (默认: aes-256-gcm)
      --socks-port <PORT>   本地 SOCKS5 端口 (默认: 1080)
      --http-port <PORT>    本地 HTTP 代理端口 (默认: 1081)
  -l, --log-level <LEVEL>   日志级别: trace/debug/info/warn/error (默认: info)
      --stop                停止正在运行的 sslocal
      --install             安装为系统服务 (Linux: systemd, macOS: launchctl)
      --uninstall           卸载系统服务
  -h, --help                显示此帮助信息

支持的加密方式:
  推荐: aes-256-gcm, aes-128-gcm, chacha20-ietf-poly1305
  2022: 2022-blake3-aes-256-gcm, 2022-blake3-aes-128-gcm

示例:
  ./start-local.sh -s 1.2.3.4 -p 8388 -k "my_password"
  ./start-local.sh -s example.com -p 443 -k "pass" -m chacha20-ietf-poly1305
  ./start-local.sh --stop
  sudo ./start-local.sh -s 1.2.3.4 -p 8388 -k "pass" --install   # Linux
  ./start-local.sh -s 1.2.3.4 -p 8388 -k "pass" --install         # macOS
  sudo ./start-local.sh --uninstall                                 # Linux
  ./start-local.sh --uninstall                                      # macOS

代理使用:
  curl --proxy socks5h://127.0.0.1:1080 https://www.google.com
  curl --proxy http://127.0.0.1:1081 https://www.google.com
  export ALL_PROXY=socks5h://127.0.0.1:1080

EOF
    exit 0
}

# ==================== 参数解析 ====================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                SERVER_ADDR="$2"; shift 2 ;;
            -p|--port)
                SERVER_PORT="$2"; shift 2 ;;
            -k|--password)
                SS_PASSWORD="$2"; shift 2 ;;
            -m|--method)
                SS_METHOD="$2"; shift 2 ;;
            --socks-port)
                SOCKS_PORT="$2"; shift 2 ;;
            --http-port)
                HTTP_PORT="$2"; shift 2 ;;
            -l|--log-level)
                LOG_LEVEL="$2"; shift 2 ;;
            --stop)
                do_stop; exit 0 ;;
            --install)
                ACTION="install" ; shift ;;
            --uninstall)
                do_uninstall; exit 0 ;;
            -h|--help)
                show_help ;;
            *)
                log_error "未知参数: $1"
                show_help ;;
        esac
    done
}

# ==================== 检查环境 ====================
check_env() {
    if [[ ! -x "$SSLOCAL" ]]; then
        log_error "找不到 sslocal: $SSLOCAL"
        if [[ "$PLATFORM" == "macos" && "$ARCH_TYPE" == "arm64" ]]; then
            log_error "请确认 bin/aarch64-musl/sslocal 存在且有执行权限"
        else
            log_error "请确认 bin/x86_64-gnu/sslocal 存在且有执行权限"
        fi
        exit 1
    fi
    log_info "平台: $OS_TYPE ($ARCH_TYPE) | sslocal: $SSLOCAL"
}

# ==================== 交互输入 ====================
interactive_input() {
    if [[ -z "$SERVER_ADDR" ]]; then
        read -rp "请输入服务器地址: " SERVER_ADDR
        if [[ -z "$SERVER_ADDR" ]]; then
            log_error "服务器地址不能为空"
            exit 1
        fi
    fi

    if [[ -z "$SS_PASSWORD" ]]; then
        read -rsp "请输入密码: " SS_PASSWORD
        echo
        if [[ -z "$SS_PASSWORD" ]]; then
            log_error "密码不能为空"
            exit 1
        fi
    fi

    echo
    log_info "========== 配置确认 =========="
    log_info "服务器:       $SERVER_ADDR:$SERVER_PORT"
    log_info "加密方式:     $SS_METHOD"
    log_info "SOCKS5 代理:  127.0.0.1:$SOCKS_PORT"
    log_info "HTTP 代理:    127.0.0.1:$HTTP_PORT"
    log_info "日志级别:     $LOG_LEVEL"
    log_info "=============================="
    echo
}

# ==================== 生成配置 ====================
generate_config() {
    mkdir -p "$RUN_DIR"

    # 生成 log4rs 配置
    cat > "$RUN_DIR/log4rs.yml" << YAML
refresh_rate: 30 seconds
appenders:
  stdout:
    kind: console
    encoder:
      pattern: "{d} {h({l}):<5} {m}{n}"
  file:
    kind: rolling_file
    path: ${RUN_DIR}/sslocal.log
    encoder:
      kind: pattern
      pattern: "{d(%Y-%m-%d %H:%M:%S)} {h({l}):<5} {m}{n}"
    policy:
      trigger:
        kind: size
        limit: 10 mb
      roller:
        kind: fixed_window
        pattern: ${RUN_DIR}/sslocal.{}.log
        count: 3
root:
  level: ${LOG_LEVEL}
  appenders:
    - stdout
    - file
YAML

    # 生成 sslocal 配置
    cat > "$RUN_DIR/config.json" << JSON
{
  "locals": [
    {
      "local_address": "127.0.0.1",
      "local_port": ${SOCKS_PORT}
    },
    {
      "local_address": "127.0.0.1",
      "local_port": ${HTTP_PORT},
      "protocol": "http"
    }
  ],
  "servers": [
    {
      "server": "${SERVER_ADDR}",
      "server_port": ${SERVER_PORT},
      "password": "${SS_PASSWORD}",
      "method": "${SS_METHOD}",
      "mode": "tcp_and_udp"
    }
  ],
  "timeout": 15,
  "nofile": 32768,
  "ipv6_first": false,
  "log": {
    "config_path": "${RUN_DIR}/log4rs.yml"
  },
  "runtime": {
    "mode": "multi_thread"
  }
}
JSON

    # 配置文件权限限制为仅当前用户可读写
    chmod 600 "$RUN_DIR/config.json"
    log_info "配置已生成: $RUN_DIR/config.json"
}

# ==================== 生成系统级配置 ====================
generate_install_config() {
    local conf_dir="$1"
    local log_dir="$2"

    # 生成 log4rs 配置
    cat > "$conf_dir/log4rs.yml" << SYAML
refresh_rate: 30 seconds
appenders:
  stdout:
    kind: console
    encoder:
      pattern: "{d} {h({l}):<5} {m}{n}"
  file:
    kind: rolling_file
    path: ${log_dir}/sslocal.log
    encoder:
      kind: pattern
      pattern: "{d(%Y-%m-%d %H:%M:%S)} {h({l}):<5} {m}{n}"
    policy:
      trigger:
        kind: size
        limit: 10 mb
      roller:
        kind: fixed_window
        pattern: ${log_dir}/sslocal.{}.log
        count: 5
        base: 1
root:
  level: ${LOG_LEVEL}
  appenders:
    - file
SYAML

    # 生成 sslocal 配置
    cat > "$conf_dir/config.json" << SJSON
{
  "locals": [
    {
      "local_address": "127.0.0.1",
      "local_port": ${SOCKS_PORT}
    },
    {
      "local_address": "127.0.0.1",
      "local_port": ${HTTP_PORT},
      "protocol": "http"
    }
  ],
  "servers": [
    {
      "server": "${SERVER_ADDR}",
      "server_port": ${SERVER_PORT},
      "password": "${SS_PASSWORD}",
      "method": "${SS_METHOD}",
      "mode": "tcp_and_udp"
    }
  ],
  "timeout": 15,
  "nofile": 32768,
  "ipv6_first": false,
  "log": {
    "config_path": "${conf_dir}/log4rs.yml"
  },
  "runtime": {
    "mode": "multi_thread"
  }
}
SJSON

    chmod 600 "$conf_dir/config.json"
}

# ==================== 安装服务 (Linux systemd) ====================
do_install_linux() {
    if [[ $EUID -ne 0 ]]; then
        log_error "安装 systemd 服务需要 root 权限，请使用 sudo"
        exit 1
    fi

    log_step "安装 sslocal 到 $INSTALL_DIR ..."
    install -m 755 "$SSLOCAL" "$INSTALL_DIR/sslocal"

    log_step "生成配置到 $CONFIG_DIR ..."
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    generate_install_config "$CONFIG_DIR" "$LOG_DIR"

    log_step "创建 systemd 服务 ..."
    cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=Shadowsocks-rust Local Proxy (sslocal)
Documentation=https://github.com/shadowsocks/shadowsocks-rust
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
LimitNOFILE=32768
ExecStart=${INSTALL_DIR}/sslocal -c ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5
StandardOutput=null
StandardError=journal

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${LOG_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    echo
    log_info "============================================"
    log_info "  sslocal systemd 服务安装成功!"
    log_info "--------------------------------------------"
    log_info "  SOCKS5 代理: socks5h://127.0.0.1:$SOCKS_PORT"
    log_info "  HTTP   代理: http://127.0.0.1:$HTTP_PORT"
    log_info "--------------------------------------------"
    log_info "  状态:  systemctl status $SERVICE_NAME"
    log_info "  停止:  systemctl stop $SERVICE_NAME"
    log_info "  启动:  systemctl start $SERVICE_NAME"
    log_info "  重启:  systemctl restart $SERVICE_NAME"
    log_info "  日志:  journalctl -u $SERVICE_NAME -f"
    log_info "  卸载:  sudo $0 --uninstall"
    log_info "============================================"
}

# ==================== 安装服务 (macOS launchctl) ====================
do_install_macos() {
    log_step "安装 sslocal 到 $INSTALL_DIR ..."
    sudo mkdir -p "$INSTALL_DIR"
    sudo cp "$SSLOCAL" "$INSTALL_DIR/sslocal"
    sudo chmod 755 "$INSTALL_DIR/sslocal"

    log_step "生成配置到 $CONFIG_DIR ..."
    sudo mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    sudo chown "$(whoami)" "$CONFIG_DIR" "$LOG_DIR"
    generate_install_config "$CONFIG_DIR" "$LOG_DIR"

    log_step "创建 launchctl plist ..."
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/sslocal</string>
        <string>-c</string>
        <string>${CONFIG_DIR}/config.json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/sslocal.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/sslocal.stderr.log</string>
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>32768</integer>
    </dict>
</dict>
</plist>
PLIST

    launchctl load "$PLIST_FILE"

    echo
    log_info "============================================"
    log_info "  sslocal launchctl 服务安装成功!"
    log_info "--------------------------------------------"
    log_info "  SOCKS5 代理: socks5h://127.0.0.1:$SOCKS_PORT"
    log_info "  HTTP   代理: http://127.0.0.1:$HTTP_PORT"
    log_info "--------------------------------------------"
    log_info "  状态:  launchctl list | grep $PLIST_LABEL"
    log_info "  停止:  launchctl unload $PLIST_FILE"
    log_info "  启动:  launchctl load $PLIST_FILE"
    log_info "  日志:  tail -f $LOG_DIR/sslocal.log"
    log_info "  配置:  $CONFIG_DIR/config.json"
    log_info "  卸载:  $0 --uninstall"
    log_info "============================================"
    log_info ""
    log_info "  提示: 可在 系统设置 → 网络 → 代理 中配置系统级代理"
}

# ==================== 安装入口 ====================
do_install() {
    if [[ "$PLATFORM" == "macos" ]]; then
        do_install_macos
    else
        do_install_linux
    fi
}

# ==================== 卸载服务 (Linux) ====================
do_uninstall_linux() {
    if [[ $EUID -ne 0 ]]; then
        log_error "卸载 systemd 服务需要 root 权限，请使用 sudo"
        exit 1
    fi

    log_step "停止并禁用 $SERVICE_NAME 服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    log_step "清理文件..."
    rm -f "$SERVICE_FILE"
    rm -f "$INSTALL_DIR/sslocal"
    rm -rf "$CONFIG_DIR"
    rm -rf "$LOG_DIR"
    systemctl daemon-reload

    log_info "sslocal systemd 服务已卸载"
}

# ==================== 卸载服务 (macOS) ====================
do_uninstall_macos() {
    log_step "停止 $PLIST_LABEL 服务..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true

    log_step "清理文件..."
    rm -f "$PLIST_FILE"
    sudo rm -f "$INSTALL_DIR/sslocal"
    sudo rm -rf "$CONFIG_DIR"
    sudo rm -rf "$LOG_DIR"

    log_info "sslocal launchctl 服务已卸载"
}

# ==================== 卸载入口 ====================
do_uninstall() {
    if [[ "$PLATFORM" == "macos" ]]; then
        do_uninstall_macos
    else
        do_uninstall_linux
    fi
}

# ==================== 停止服务 ====================
do_stop() {
    local pidfile="$RUN_DIR/sslocal.pid"
    if [[ -f "$pidfile" ]]; then
        local pid
        pid=$(cat "$pidfile")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log_info "已停止 sslocal (PID: $pid)"
        else
            log_warn "进程 $pid 已不存在"
        fi
        rm -f "$pidfile"
    else
        log_warn "未找到 PID 文件，尝试查找进程..."
        if pkill -f "$SSLOCAL" 2>/dev/null; then
            log_info "已停止 sslocal"
        else
            log_warn "没有正在运行的 sslocal 进程"
        fi
    fi
}

# ==================== 启动代理 ====================
start_proxy() {
    local pidfile="$RUN_DIR/sslocal.pid"

    # 检查是否已在运行
    if [[ -f "$pidfile" ]]; then
        local old_pid
        old_pid=$(cat "$pidfile")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_warn "sslocal 已在运行 (PID: $old_pid)"
            read -rp "是否先停止再重新启动? [Y/n] " answer
            if [[ "${answer,,}" != "n" ]]; then
                do_stop
            else
                exit 0
            fi
        fi
    fi

    log_step "启动 sslocal..."
    nohup "$SSLOCAL" -c "$RUN_DIR/config.json" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$pidfile"

    # 短暂等待后检查进程
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        echo
        log_info "============================================"
        log_info "  sslocal 启动成功! (PID: $pid)"
        log_info "--------------------------------------------"
        log_info "  SOCKS5 代理: socks5h://127.0.0.1:$SOCKS_PORT"
        log_info "  HTTP   代理: http://127.0.0.1:$HTTP_PORT"
        log_info "--------------------------------------------"
        log_info "  测试:  curl --proxy socks5h://127.0.0.1:$SOCKS_PORT https://www.google.com"
        log_info "  设置:  export ALL_PROXY=socks5h://127.0.0.1:$SOCKS_PORT"
        log_info "  日志:  tail -f $RUN_DIR/sslocal.log"
        log_info "  停止:  $0 --stop"
        log_info "============================================"
    else
        log_error "sslocal 启动失败，请检查日志: $RUN_DIR/sslocal.log"
        rm -f "$pidfile"
        exit 1
    fi
}

# ==================== 主流程 ====================
main() {
    parse_args "$@"
    check_env
    interactive_input

    if [[ "${ACTION:-}" == "install" ]]; then
        generate_config
        do_install
    else
        generate_config
        start_proxy
    fi
}

main "$@"
