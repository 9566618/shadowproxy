# ShadowProxy

OpenWrt 透明代理解决方案，基于 shadowsocks-rust，提供 LuCI 图形界面配置。

## 功能特性

- 🚀 基于 shadowsocks-rust 的高性能透明代理
- 🌐 支持 TCP/UDP 透明代理 (tproxy)
- 🔍 智能 DNS 分流（国内直连，国外代理）
- 📋 ACL 规则支持（域名、IP 分流）
- 🖥️ LuCI 图形界面配置
- ⚡ 支持 SOCKS5 和 HTTP 代理
- 🔄 多服务器负载均衡
- 🛡️ 重放攻击防护

## 支持架构

| 架构 | 说明 |
|------|------|
| aarch64-musl | ARM64 架构 (树莓派4、R4S 等) |
| x86_64-musl | x86_64 musl 编译 |
| x86_64-gnu | x86_64 glibc 编译 |
| mips-musl | MIPS 大端 (部分路由器) |
| mipsel-musl | MIPS 小端 (部分路由器) |

> ⚠️ **安全说明**：本项目提供的 `sslocal` 二进制文件部分编译包含优化混淆。如有安全顾虑，建议：
> 1. 使用 [shadowsocks-rust 官方 Release](https://github.com/shadowsocks/shadowsocks-rust/releases) 二进制文件
> 2. 选择更复杂的加密方式（如 `aes-256-gcm` 或 `chacha20-ietf-poly1305`）
> 3. 或从源码自行编译：`cargo build --release --features local-dns,local-redir,security-replay-attack-detect`

## 安装

### 方式一：IPK 安装包（推荐）

1. 从 [Releases](https://github.com/user/shadowproxy/releases) 下载对应架构的 ipk 文件
2. 在 OpenWrt 管理界面：`系统` → `软件包` → `上传安装`
3. 或通过命令行安装：

```bash
scp shadowproxy_*.ipk root@router:/tmp/
ssh root@router "opkg install /tmp/shadowproxy_*.ipk"
```

### 方式二：手动安装

```bash
# 1. 复制 sslocal 可执行文件
scp bin/<架构>/sslocal root@router:/usr/bin/sslocal
ssh root@router "chmod +x /usr/bin/sslocal"

# 2. 复制 LuCI 界面文件
scp -r htdocs/* root@router:/www/

# 3. 复制配置和脚本文件
scp -r root/* root@router:/

# 4. 启用服务
ssh root@router "/etc/init.d/shadowproxy enable"
```

### 依赖安装

ShadowProxy 依赖 `nftables`，请确保已安装：

```bash
opkg update
opkg install nftables kmod-nft-tproxy
```

## 配置使用

### 基础配置

1. 打开 LuCI 界面：`服务` → `ShadowProxy`
2. 在「主设置」中配置：
   - **启用**：开启服务
   - **本地 DNS**：国内 DNS 服务器（如 `223.5.5.5`，阿里 DNS）
   - **远程 DNS**：国外 DNS 服务器（如 `1.1.1.1`，Cloudflare DNS）
   - **透明代理端口**：默认 `60080`
   - **DNS 端口**：默认 `5300`
   - **SOCKS5 端口**：可选，设为 `0` 禁用
   - **HTTP 代理端口**：可选，设为 `0` 禁用

> 💡 本地 DNS 可在 `/tmp/resolv.conf.ppp` 或 `/tmp/resolv.conf.d/resolv.conf.auto` 中查看运营商分配的 DNS

### 服务器配置

1. 在「服务器」标签页添加 Shadowsocks 服务器
2. 填写服务器信息：
   - **服务器地址**：支持 IPv4 和 IPv6
   - **端口**：服务器端口
   - **密码**：连接密码
   - **加密方式**：推荐 `aes-256-gcm` 或 `chacha20-ietf-poly1305`

> 💡 建议同时配置 IPv4 和 IPv6 服务器，系统会自动选择最优线路

### 高级设置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| worker_count | 工作线程数，**应设为 CPU 核数** | 4 |
| client_cache_size | DNS 缓存大小 | 64 |
| no_delay | TCP_NODELAY，关掉 Nagle 降延迟 | 启用 |
| keep_alive | TCP 保活时间(秒) | 15 |
| nofile | 最大文件描述符 | 10240 |
| fast_open | TCP Fast Open | 禁用 |
| mptcp | 多路径 TCP | 禁用 |

> 💡 `worker_count` 设得比 CPU 核数大只会浪费内存和调度开销，不会提升吞吐。调优细节见 [性能调优](#性能调优)

### 应用配置

配置完成后点击「保存并应用」，服务将自动启动。

## 配置文件说明

所有配置文件位于 `/etc/shadowproxy/` 目录：

| 文件 | 说明 |
|------|------|
| `config-template.json` | shadowsocks-rust 配置模板 |
| `config.json` | 运行时生成的配置文件 |
| `shadowproxy-redir.acl` | 透明代理 ACL 规则 |
| `shadowproxy-dns.acl` | DNS 分流 ACL 规则 |
| `bypass_ipset.acl` | 绕过代理的 IP 列表 |
| `chnip4.ips` | 中国 IPv4 地址段 |
| `chnip6.ips` | 中国 IPv6 地址段 |
| `shadowproxy.nft` | nftables 规则 |

## 服务管理

```bash
# 启动服务
/etc/init.d/shadowproxy start

# 停止服务
/etc/init.d/shadowproxy stop

# 重启服务
/etc/init.d/shadowproxy restart

# 查看服务状态
/etc/init.d/shadowproxy status

# 开机自启
/etc/init.d/shadowproxy enable

# 禁用自启
/etc/init.d/shadowproxy disable
```

## 搭建 Shadowsocks 服务端

本项目提供了一键部署脚本和 `ssserver` 可执行文件（x86_64-gnu），方便快速搭建服务端。

### 一键部署（推荐）

使用 `config/setup-server.sh` 脚本可自动完成安装、配置和优化：

```bash
# 下载脚本到服务器
scp config/setup-server.sh root@your-server:/root/

# SSH 登录服务器执行
ssh root@your-server
chmod +x setup-server.sh

# 交互式安装
./setup-server.sh

# 或命令行安装
./setup-server.sh -p 8388 -k "your_password" -m aes-256-gcm
```

脚本功能：
- ✅ 自动安装 ssserver 到 `/usr/local/bin/`
- ✅ 生成优化的配置文件
- ✅ 配置 systemd 服务（支持开机自启、自动重启）
- ✅ 配置防火墙规则（支持 ufw/firewalld/iptables）
- ✅ 优化系统参数（TCP BBR、缓冲区等）
- ✅ 安全加固（systemd 沙箱）

#### 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-p, --port` | 服务端口 | 8388 |
| `-k, --password` | 连接密码 | (必填) |
| `-m, --method` | 加密方式 | aes-256-gcm |
| `-w, --workers` | 工作线程数 | 16 |
| `-t, --timeout` | UDP 超时(秒) | 300 |
| `--uninstall` | 卸载服务 | - |

#### 服务管理

```bash
# 启动/停止/重启
systemctl start shadowsocks
systemctl stop shadowsocks
systemctl restart shadowsocks

# 查看状态和日志
systemctl status shadowsocks
journalctl -u shadowsocks -f
```

### 手动部署

如需手动部署，可参考以下步骤：

```bash
# 1. 复制可执行文件
scp bin/x86_64-gnu/ssserver root@server:/usr/local/bin/
ssh root@server "chmod +x /usr/local/bin/ssserver"

# 2. 创建配置目录和文件
ssh root@server "mkdir -p /etc/shadowsocks /var/log/shadowsocks"
scp config/config.json root@server:/etc/shadowsocks/
scp config/log4rs.yml root@server:/etc/shadowsocks/

# 3. 修改配置（设置密码等）
ssh root@server "vi /etc/shadowsocks/config.json"

# 4. 配置 systemd 服务
scp config/shadowsocks.service root@server:/etc/systemd/system/
ssh root@server "systemctl daemon-reload && systemctl enable --now shadowsocks"
```

## 本地代理快速启动

本项目提供了 `config/start-local.sh` 脚本，快速启动本地 SOCKS5 / HTTP 代理。脚本自动检测平台和 CPU 架构，选择对应的 `sslocal` 二进制文件：

| 平台 | 架构 | 使用的二进制 |
|------|------|-------------|
| Linux | x86_64 | `bin/x86_64-gnu/sslocal` |
| macOS | Intel (x86_64) | `bin/x86_64-apple/sslocal` |
| macOS | Apple Silicon (arm64) | `bin/aarch64-apple/sslocal` |

> ⚠️ macOS 必须用 `bin/*-apple/` 下的 Mach-O 二进制。`bin/*-musl` 和 `bin/*-gnu` 是 Linux ELF，在 macOS 上执行会直接报 `Exec format error`

### 快速启动（后台进程）

```bash
# Linux: 复制脚本到目标机器
scp config/start-local.sh user@host:~/gits/shadowproxy/config/

# 命令行启动（macOS / Linux 通用，自动选择二进制）
./config/start-local.sh -s <服务器地址> -p 8388 -k "your_password"

# 交互式启动（会提示输入服务器和密码）
./config/start-local.sh

# 停止代理
./config/start-local.sh --stop
```

启动后可直接使用：

```bash
# 设置全局代理
export ALL_PROXY=socks5h://127.0.0.1:1080

# 或指定代理访问
curl --proxy socks5h://127.0.0.1:1080 https://www.google.com
curl --proxy http://127.0.0.1:1081 https://www.google.com
```

### 安装为系统服务

脚本自动检测平台，Linux 使用 systemd，macOS 使用 launchctl：

#### Linux (systemd)

```bash
sudo ./config/start-local.sh -s <服务器地址> -p 8388 -k "your_password" --install

# 管理服务
systemctl status sslocal
systemctl restart sslocal
journalctl -u sslocal -f

# 卸载
sudo ./config/start-local.sh --uninstall
```

#### macOS (launchctl)

```bash
# 安装（sslocal 和配置安装到 /usr/local/，plist 安装到 ~/Library/LaunchAgents/）
./config/start-local.sh -s <服务器地址> -p 8388 -k "your_password" --install

# 管理服务
launchctl list | grep com.shadowsocks.sslocal
launchctl unload ~/Library/LaunchAgents/com.shadowsocks.sslocal.plist   # 停止
launchctl load ~/Library/LaunchAgents/com.shadowsocks.sslocal.plist     # 启动
tail -f /usr/local/var/log/sslocal/sslocal.log

# 卸载
./config/start-local.sh --uninstall
```

> 💡 macOS 用户可在「系统设置 → 网络 → 代理」中配置系统级 SOCKS5/HTTP 代理，指向 `127.0.0.1:1080` / `127.0.0.1:1081`

### 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-s, --server` | 远程服务器地址 | (必填) |
| `-p, --port` | 远程服务器端口 | 8388 |
| `-k, --password` | 连接密码 | (必填) |
| `-m, --method` | 加密方式 | aes-256-gcm |
| `--socks-port` | 本地 SOCKS5 端口 | 1080 |
| `--http-port` | 本地 HTTP 代理端口 | 1081 |
| `-l, --log-level` | 日志级别 | info |
| `--stop` | 停止后台 sslocal | - |
| `--install` | 安装为 systemd 服务 | - |
| `--uninstall` | 卸载 systemd 服务 | - |

## 性能调优

下面每一条都对着 shadowsocks-rust 源码核对过，标注了字段所在位置，避免调到不存在或不生效的参数。

### 先说三个容易踩空的地方

**1. 收发缓冲区不能写在 config.json 里**

`inbound_send_buffer_size` / `inbound_recv_buffer_size` / `outbound_send_buffer_size` / `outbound_recv_buffer_size` 这四个只存在于内部的 `ConnectOpts`/`AcceptOpts`，**从来不从 `SSConfig` 赋值**——写进 config.json 会被静默忽略。它们只是命令行参数：

```bash
ssserver -c config.json --outbound-recv-buffer-size 4194304
```

**但通常不该设。** 显式 `setsockopt(SO_RCVBUF/SO_SNDBUF)` 会**关掉内核的接收缓冲自动调整**（`tcp_moderate_rcvbuf`）。只要 `net.core.rmem_max` / `net.ipv4.tcp_rmem` 上限给够，内核会按实际带宽时延积自动伸缩，比手工拍一个固定值更准。手工设小了反而会成为跨境长肥管道的瓶颈。调大内核上限，别动 socket 选项。

**2. `timeout` 是连接超时，不是空闲超时**

源码 `crates/shadowsocks/src/config.rs` 里注释写的是 `Handshake timeout (connect)`，运行时只包住 `connect_server_with_opts`。所以默认的 `15` 是合适的，**不要往大调**——调成 300 不会让长连接更稳，只会让故障服务器的切换从 15 秒变成 5 分钟。空闲连接的回收由 `keep_alive` 和 `udp_timeout` 负责。

**3. `worker_count` 设得比 CPU 核数大只有坏处**

源码 `src/config.rs` 注释：`Multithread runtime worker count, CPU count if not configured`。**留空即按核数自适应**，这是最优解。设成核数的十几倍不会提升吞吐（单机吞吐上限由核数决定），只会多出线程栈和调度开销：

| 场景 | 改动 | 效果 |
|------|------|------|
| 1 核 VPS | `worker_count: 16` → 移除 | 线程 16→1，RSS 约 11MB |
| 4 核路由器 | `worker_count: 64` → `4` | 线程 ~67→7，虚拟内存 209MB→28MB |

### 服务端 (ssserver) 推荐配置

```json
{
  "nofile": 32768,
  "udp_timeout": 300,
  "udp_max_associations": 2048,
  "no_delay": true,
  "keep_alive": 30,
  "runtime": { "mode": "multi_thread" }
}
```

| 配置项 | 作用 |
|--------|------|
| `no_delay: true` | 开 TCP_NODELAY 关掉 Nagle。默认 `false`，小包会被攒够或等 40ms 才发，视频分片请求和交互操作都会平白多一截延迟 |
| `keep_alive: 30` | 探测死连接，回收对端已消失的会话和 NAT 表项 |
| `udp_max_associations: 2048` | UDP(QUIC/视频)关联数上限。默认**无上限**，小内存机器需要兜底 |
| `runtime` 不写 `worker_count` | 按 CPU 核数自适应，见上 |

### 客户端 (sslocal / OpenWrt) 推荐配置

OpenWrt 侧通过 uci 配置，`/etc/init.d/shadowproxy` 会套用到模板：

```bash
uci set shadowproxy.settings.worker_count=4     # = CPU 核数
uci set shadowproxy.settings.no_delay=1
uci commit shadowproxy && /etc/init.d/shadowproxy restart
```

`fast_open`（TCP Fast Open）默认关闭，建议保持——很多中间设备会丢弃带 TFO 数据的 SYN，导致首包重传，反而更慢。

### 系统参数

代理节点和路由器都建议：

```bash
# 跨境长肥管道: BBR 比 cubic 更能吃满带宽，且不会把缓冲区灌满
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq            # 路由器用 fq_codel

# 关键: 空闲后不要把拥塞窗口打回初始值
net.ipv4.tcp_slow_start_after_idle = 0

# 给足自动调整的上限（不要去设 socket 的 SO_RCVBUF）
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
```

`tcp_slow_start_after_idle = 0` 对看视频影响最直接：播放器缓冲满了就暂停拉流，几秒后再拉，此时拥塞窗口已被重置回初始值，每次恢复都要重新爬坡——表现就是码率反复降级、来回卡顿。

OpenWrt 上 BBR 模块通常有但没加载：

```bash
modprobe tcp_bbr
echo tcp_bbr > /etc/modules.d/99-tcp-bbr      # 开机自动加载
sysctl -n net.ipv4.tcp_available_congestion_control   # 确认出现 bbr
```

路由器用 `fq_codel` 而非 `fq`，治的是 bufferbloat：上传占满时交互流量被大流堵在队列里，是视频卡顿和游戏延迟飙升的主因。注意 `default_qdisc` **只对新建的 qdisc 生效**，已有接口要手动换：

```bash
for dev in pppoe-wan eth0 eth1; do tc qdisc replace dev $dev root fq_codel; done
tc qdisc show | grep -v noqueue      # 确认不再是 pfifo_fast
```

> 💡 如果上下行带宽已知，装 `sqm-scripts` 做限速整形（cake）效果比裸 fq_codel 更好，但需要填真实线路速率，填错反而限制带宽。

### 效果验证

```bash
# 线程数是否降下来
PID=$(pidof ssserver); ls /proc/$PID/task | wc -l

# 拥塞算法/qdisc 是否生效
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc net.ipv4.tcp_slow_start_after_idle

# 实际连接用的拥塞算法
ss -tin | grep -o "bbr\|cubic" | sort | uniq -c
```

## WireGuard 隧道配置

`config/wireguard-tunnel-setup.sh` 用于把代理节点的出站流量再经 WireGuard 转发一跳（多跳代理），支持 IPv4/IPv6 双栈。

核心机制是 **fwmark + 策略路由**：shadowsocks 给出站流量打 fwmark，客户端把带该 fwmark 的包导进隧道，其余流量照常走本地出口。

### 两种拓扑

**拓扑 A — 多个代理节点共用一个出口**（在出口端 `--add-peer` 即可扩容）

```
[代理节点1 client .2] ──┐
[代理节点2 client .3] ──┼── WireGuard ──> [出口 server .1] ──> 互联网
[代理节点3 client .4] ──┘
```

**拓扑 B — 一个代理节点接多个出口，按 fwmark 分流**（同机起多个 client 接口）

```
                     ┌─ ss :8081 → fwmark 255 → table 100 → wg0 → [出口 A] ──> 互联网
[客户端] ──ss──> 代理节点 ─┤
                     └─ ss :8082 → fwmark 254 → table 101 → wg1 → [出口 B] ──> 互联网
```

两种可以叠加。每个接口用独立的 `-w` / `-m` / `-t`，密钥按接口名自动隔离。

| 角色 | 说明 |
|------|------|
| **server (出口端)** | WireGuard Server，隧道 IP `.1`，监听等待连接，NAT 转发到互联网 |
| **client (代理节点)** | WireGuard Client，隧道 IP `.2` 起，主动连接出口端，按 fwmark 引流 |

### 快速上手：一条隧道

下面用文档示例地址：代理节点 `198.51.100.5`，出口端 `203.0.113.10`。

#### 1. 先各自建密钥，再互填公钥

`--gen-key` 是幂等的（已存在就直接打印现有公钥），这样两端都不必事先知道对方的公钥：

```bash
# 出口端
出口$ ./wireguard-tunnel-setup.sh --gen-key
# 代理节点
代理$ ./wireguard-tunnel-setup.sh --gen-key
```

脚本化取值用 `--show-pubkey`，它只往 stdout 打一行公钥：

```bash
SERVER_PUB=$(ssh root@203.0.113.10 '/root/wireguard-tunnel-setup.sh --show-pubkey')
CLIENT_PUB=$(ssh root@198.51.100.5 '/root/wireguard-tunnel-setup.sh --show-pubkey')
```

> 💡 也可以省略 `-k` 直接跑部署。缺对端公钥时脚本不会写出 `[Peer]` 段（写空公钥会让 `wg-quick up` 直接失败），拿到公钥后补上 `-k` 重跑即可，密钥会自动复用。

#### 2. 出口端

```bash
# 仅 IPv4
./wireguard-tunnel-setup.sh -r server \
    -l 10.200.200.1/24 -i enp1s0 -k "$CLIENT_PUB"

# IPv4 + IPv6 双栈
./wireguard-tunnel-setup.sh -r server \
    -l 10.200.200.1/24 -6 fd00:200::1/64 \
    -n 10.200.200.0/24 -N fd00:200::/64 \
    -i enp1s0 --ipv6 yes -k "$CLIENT_PUB"
```

出口端会自动开启转发、配置 NAT（MASQUERADE），并在检测到 ufw 时用 `ufw allow` / `ufw route allow` 下规则。

#### 3. 代理节点

```bash
# 仅 IPv4
./wireguard-tunnel-setup.sh -r client \
    -l 10.200.200.2/24 -i eth0 \
    -e 203.0.113.10 -k "$SERVER_PUB"

# IPv4 + IPv6 双栈
./wireguard-tunnel-setup.sh -r client \
    -l 10.200.200.2/24 -6 fd00:200::2/64 \
    -i eth0 -e 203.0.113.10 -E 2001:db8::10 \
    --ipv6 yes -k "$SERVER_PUB"
```

#### 4. 验证

```bash
wg show                                    # 看 latest handshake
ping 10.200.200.1                          # 隧道内连通性
curl -s4 --interface wg0 ifconfig.me       # 应返回出口端的公网 IP
```

更贴近真实路径的验证是带 fwmark 发包（shadowsocks 用 `SO_MARK` 就是这么做的）：

```bash
python3 - <<'PY'
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, 36, 255)   # 36 = SO_MARK
s.connect(("ifconfig.me", 80))
s.send(b"GET /ip HTTP/1.0\r\nHost: ifconfig.me\r\nUser-Agent: curl/8\r\n\r\n")
print("源地址:", s.getsockname()[0])        # 应为隧道 IP 10.200.200.2
print(s.recv(4096).decode().split("\r\n\r\n")[-1].strip())   # 应为出口端公网 IP
PY
```

源地址落在隧道 IP 上很关键——出口端的 MASQUERADE 只匹配隧道网段，源地址不对流量会被丢掉。

#### 5. 扩容：再加一个代理节点

在出口端热加载，无需重启：

```bash
./wireguard-tunnel-setup.sh --add-peer -k <新客户端公钥> -a 10.200.200.3/32
```

> 💡 出口端固定 `.1`，客户端从 `.2` 起递增。

### 进阶：一个节点接多个出口

在同一台代理节点上再起一个 `wg1`，把 fwmark 254 的流量送到另一个出口。**关键是三样东西都要错开**：接口名 `-w`、fwmark `-m`、路由表 `-t`，隧道网段也要换一个。

```bash
# ① 代理节点: 为 wg1 生成独立密钥 (不影响已有的 wg0)
代理$ ./wireguard-tunnel-setup.sh --gen-key -w wg1

# ② 出口 B: 用一个新网段，把上一步的公钥填进去
出口B$ ./wireguard-tunnel-setup.sh -r server \
    -l 10.200.201.1/24 -6 fd00:201::1/64 \
    -n 10.200.201.0/24 -N fd00:201::/64 \
    -i enp1s0 --ipv6 yes -k <wg1 公钥>

# ③ 代理节点: 起 wg1，走 fwmark 254 / table 101
代理$ ./wireguard-tunnel-setup.sh -r client -w wg1 \
    -l 10.200.201.2/24 -6 fd00:201::2/64 \
    -i eth0 -e 203.0.113.20 -E 2001:db8::20 \
    -m 254 -t 101 --ipv6 yes -k <出口B 公钥>
```

完成后策略路由长这样：

```
$ ip rule list
50:    from all to 203.0.113.10 lookup main      # 出口 A 旁路，避免路由环
50:    from all to 203.0.113.20 lookup main      # 出口 B 旁路
100:   from all fwmark 0xff lookup 100           # 255 → wg0
100:   from all fwmark 0xfe lookup 101           # 254 → wg1
```

几点说明：

- **client 默认不占用固定 UDP 端口**。不传 `-p` 时脚本不写 `ListenPort`，由内核分配随机端口——否则同机第二个接口会因端口被占用而 `wg-quick up` 失败。需要固定端口再传 `-p`。
- **对端端口用 `-P` 单独指定**。`-p` 只管本机监听，`-P` 只管连到对端哪个端口，两者互不影响；不传 `-P` 时沿用 `-p`（默认 51820）。
- **密钥按接口名隔离**，存放在 `/etc/wireguard/<接口名>_private.key`。

### 与 shadowsocks 配合

shadowsocks-rust 的 `outbound_fwmark` 决定出站流量打什么标记。单出口时用默认的 255 即可；多出口就给每个 server 配不同的 fwmark，和上面的 `-m` 对应起来：

```json
{
  "servers": [
    { "server": "::", "server_port": 8081, "password": "...",
      "method": "aes-256-gcm", "mode": "tcp_and_udp", "outbound_fwmark": 255 },
    { "server": "::", "server_port": 8082, "password": "...",
      "method": "aes-256-gcm", "mode": "tcp_and_udp", "outbound_fwmark": 254 }
  ]
}
```

这样客户端连 `8081` 从出口 A 出去、连 `8082` 从出口 B 出去。改完 `systemctl restart shadowsocks` 生效。

若某个 fwmark 还没有对应的隧道，该流量会落到主路由表，也就是从代理节点本地直出——不会中断，只是没走隧道。

#### ⚠️ 版本要求：per-server `outbound_fwmark` 需要 v1.19.0+

`outbound_fwmark` 可以写在两个位置，语义不同：

| 位置 | 作用 | 要求 |
|------|------|------|
| 顶层 | 所有 server 的默认值 | 所有版本 |
| `servers[]` 条目内 | 覆盖该 server 的默认值 | **shadowsocks-rust v1.19.0+** |

**v1.18.2 及更早版本的 `SSServerExtConfig` 没有 `outbound_fwmark` 字段，而配置解析又没有开 `deny_unknown_fields`——所以写在 server 条目里的标记会被静默忽略，不报错、不警告，流量直接从本地出去。** 多出口分流会整个失效且毫无提示，排查起来很费劲。

调用链（源码位置，便于自行核对）：

```
config.rs        SSServerExtConfig.outbound_fwmark  → server_instance.outbound_fwmark
server/mod.rs    connect_opts.fwmark = config.outbound_fwmark    // 顶层作为模板
                 connect_opts.clone() → if let Some(m) = inst.outbound_fwmark { … }  // 逐 server 覆盖
net/sys/unix/linux/mod.rs    setsockopt(SOL_SOCKET, SO_MARK, …)  // 需要 CAP_NET_ADMIN(root)
```

> 📌 本项目 `bin/x86_64-gnu/ssserver` 为定制编译版，`--version` 显示 `1.18.2`，但**已包含** per-server `outbound_fwmark` 支持。换用官方 Release 二进制时请确认版本 ≥ 1.19.0。

**验证生效（无需造测试流量）**：直接看 ssserver 出站连接的源地址——打上标记后源地址会落在隧道 IP 上，没打标记则是本机公网 IP。

```bash
ss -tnp state established | grep ssserver | awk '{print $3}' | sed 's/:[0-9]*$//' | sort | uniq -c | sort -rn
```

```
     37 10.200.200.2              ← 出站，走了 wg0 隧道，fwmark 生效 ✓
      2 [fd00:200::2]             ← 出站 IPv6，同上
     39 [::ffff:198.51.100.5]     ← 客户端连进来的入站连接，本机地址，正常
```

若出站连接的源地址是本机公网 IP 而非隧道 IP，说明 fwmark 没生效——先查版本，再查 `ip rule` 里有没有对应的规则。

### 密钥管理

| 命令 | 用途 |
|------|------|
| `--gen-key [-w 接口]` | 生成并打印公钥；已存在则直接复用（幂等，可重复执行） |
| `--show-pubkey [-w 接口]` | 只输出一行公钥到 stdout，供脚本取值 |

密钥文件位于 `/etc/wireguard/<接口名>_private.key` 和 `_public.key`。要轮换密钥，先删除这两个文件再 `--gen-key`，然后把新公钥同步给对端。

> 📌 旧版本按角色命名（`client_*.key` / `server_*.key`）。为兼容已部署的节点，`wg0` 在只有旧命名密钥时会继续沿用它，升级脚本不会导致现有隧道换密钥断连；`wg1` 及之后的接口一律用接口名。

### 运维命令

```bash
# 交互式配置（新手推荐）
./wireguard-tunnel-setup.sh

# 查看某接口当前配置、策略路由和运行状态
./wireguard-tunnel-setup.sh --show-config -w wg1

# 卸载指定接口（只清理该接口自己的 fwmark/路由表/旁路规则，不影响同机其他隧道）
./wireguard-tunnel-setup.sh --uninstall -w wg1

# 自动化部署：跳过所有确认
./wireguard-tunnel-setup.sh -r client -l 10.200.200.2/24 -i eth0 -e 203.0.113.10 -y

# 日常排查
wg show
systemctl restart wg-quick@wg1
journalctl -u wg-quick@wg1 -f
```

### 完整参数列表

```bash
./wireguard-tunnel-setup.sh -h
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-r, --role` | 角色：`server`(出口端) 或 `client`(代理节点) | - |
| `-l, --local-ip` | 本机隧道 IPv4，如 `10.200.200.1/24` | - |
| `-6, --local-ip6` | 本机隧道 IPv6，如 `fd00:200::1/64` | - |
| `-i, --interface` | 物理网卡接口名 | - |
| `-e, --endpoint` | 出口端公网 IPv4 (仅 client) | - |
| `-E, --endpoint6` | 出口端公网 IPv6 (仅 client) | - |
| `-k, --peer-key` | 对端公钥；不填则不写 `[Peer]`，补齐后重跑 | - |
| `-p, --port` | 本机监听端口；client 不指定则用随机端口 | server 51820 |
| `-P, --peer-port` | 对端端口 (仅 client) | 同 `-p` |
| `-w, --wg-interface` | WireGuard 接口名 | wg0 |
| `-m, --fwmark` | fwmark 值 (仅 client) | 255 |
| `-t, --table` | 策略路由表 ID (仅 client) | 100 |
| `-n, --client-net` | 客户端隧道 IPv4 网段 (仅 server) | 自动推断 |
| `-N, --client-net6` | 客户端隧道 IPv6 网段 (仅 server) | fd00:200::/64 |
| `-a, --allowed-ips` | 对端 AllowedIPs | 自动生成 |
| `--ipv6` | IPv6 模式：`auto` / `yes` / `no` | auto |
| `--keepalive` | PersistentKeepalive 秒数 | 25 |
| `--gen-key` | 生成/复用密钥并打印公钥 | - |
| `--show-pubkey` | 只打印公钥 | - |
| `--add-peer` | 向出口端添加客户端（热加载） | - |
| `--show-config` | 显示当前配置 | - |
| `--uninstall` | 卸载 `-w` 指定的接口 | - |
| `-y, --yes` | 跳过确认提示 | - |

### 排查

**隧道起不来，报 `Address already in use`**
同机另一个 WireGuard 接口已占用该 UDP 端口。client 不要传 `-p`（用随机端口即可），只在需要连到非默认端口的对端时用 `-P`。

**握手成功但流量不通**
先在出口端确认 NAT 和转发：

```bash
iptables  -t nat -S POSTROUTING | grep 10.200.
ip6tables -t nat -S POSTROUTING | grep fd00:
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding    # 都应为 1
```

再确认代理节点侧源地址正确（见上面的 `SO_MARK` 验证脚本）：源地址必须是隧道 IP，否则出口端的 MASQUERADE 匹配不上。

**隧道在，但过一段时间就不转发了**
`systemd-networkd` 默认 `ManageForeign*=yes`，会在 DHCP 续租/重配网卡时把 `wg-quick` 用 `PostUp` 加的策略路由当成"外来"规则删掉。脚本会自动写入 `/etc/systemd/networkd.conf.d/10-keep-wg-routes.conf` 关掉这个行为。确认：

```bash
cat /etc/systemd/networkd.conf.d/10-keep-wg-routes.conf
ip rule list | grep fwmark        # 规则应该还在
```

**ufw 环境下重启后握手失败**
裸 `iptables` 规则会被 ufw 清掉，所以脚本在检测到 ufw active 时改用 `ufw allow` / `ufw route allow` 下规则。若手工加过裸规则，改用 ufw 的方式重下一遍。

**卸载后别的隧道也断了**
确认用的是带 `-w` 的卸载命令。脚本会从该接口自己的配置文件里解析 fwmark/路由表，只清理自己的那份。

## 常见问题

### 安装后 LuCI 界面不显示

```bash
# 清除 LuCI 缓存
rm -rf /tmp/luci-*

# 刷新浏览器缓存 (Chrome: F12 → Network → Disable cache)
```

### 无法上网（DNS 问题）

首次配置时，如果服务器信息不正确，可能导致 DNS 无法解析。

解决方法：
1. 临时禁用 ShadowProxy：`/etc/init.d/shadowproxy stop`
2. 修正服务器配置
3. 重新启动服务

### OpenWrt 21.x 兼容性

OpenWrt 21.x 需要手动安装 nftables：

```bash
opkg update
opkg install nftables kmod-nft-tproxy
```

### IPv6 支持

- 如果本地网络支持 IPv6，建议配置 IPv6 服务器
- 某些域名仅解析 IPv6 地址，没有 IPv6 服务器可能无法访问
- 如果本地只有 IPv4，可以只使用 IPv4 服务器

### DNS 解析原理

```
[客户端] → [dnsmasq] → [ShadowProxy DNS(5300)] → 根据 ACL 规则分流
                                                   ├─ 国内域名 → 本地 DNS
                                                   └─ 国外域名 → 代理远程 DNS
```

### 自定义分流规则

- 修改 `bypass_ipset.acl` 添加绕过代理的 IP
- 修改 `chnip4.ips` / `chnip6.ips` 更新中国 IP 段
- 修改 `proxy_domains.acl` 添加需要代理的域名

### 为什么不推荐使用插件？

shadowsocks-rust 的插件机制会启动额外的子进程来处理数据包，会增加硬件资源消耗。如需复杂的混淆功能，建议直接使用 v2ray 或 clash。

## 许可证

GNU General Public License v3.0