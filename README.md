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
| worker_count | 工作线程数 | 16 |
| client_cache_size | DNS 缓存大小 | 64 |
| no_delay | TCP_NODELAY | 禁用 |
| keep_alive | TCP 保活时间(秒) | 15 |
| nofile | 最大文件描述符 | 10240 |
| fast_open | TCP Fast Open | 禁用 |
| mptcp | 多路径 TCP | 禁用 |

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

## WireGuard 隧道配置

如需通过 WireGuard 隧道转发代理流量（多跳代理），可使用提供的配置脚本。

### 使用场景

```
[客户端] → [OpenWrt 路由器] → [源端服务器(香港)] → [WireGuard隧道] → [目标服务器(新加坡)] → [互联网]
```

这种架构适用于：
- 需要多跳代理提升隐私性
- 利用不同地区服务器优化线路
- 分离代理服务和出口节点

### 配置步骤

项目提供了 `config/wireguard-tunnel-setup.sh` 脚本，支持交互式和命令行两种配置方式。

#### 1. 源端服务器配置（转发端）

源端服务器运行代理服务（如 shadowsocks），将标记的流量通过 WireGuard 隧道转发到目标端。

```bash
# 交互式配置
./wireguard-tunnel-setup.sh

# 或命令行配置
./wireguard-tunnel-setup.sh -r source \
    -l 10.200.200.1/24 \
    -i eth0 \
    -e <目标端公网IP> \
    -m 255 \
    -t 100
```

参数说明：
- `-r source`：指定为源端角色
- `-l 10.200.200.1/24`：本机隧道 IP
- `-i eth0`：物理网卡接口
- `-e`：目标端服务器公网 IP
- `-m 255`：fwmark 标记值（与 shadowsocks-rust 的 `outbound_fwmark` 对应）
- `-t 100`：策略路由表 ID

#### 2. 目标端服务器配置（出口端）

目标端服务器接收隧道流量并进行 NAT 转发到互联网。

```bash
./wireguard-tunnel-setup.sh -r target \
    -l 10.200.200.2/24 \
    -i enp1s0 \
    -e <源端公网IP> \
    -s 10.200.200.0/24
```

参数说明：
- `-r target`：指定为目标端角色
- `-l 10.200.200.2/24`：本机隧道 IP
- `-i enp1s0`：物理网卡接口
- `-e`：源端服务器公网 IP
- `-s 10.200.200.0/24`：源端隧道网段（用于配置 AllowedIPs）

#### 3. 交换公钥

配置完成后，需要交换两端的 WireGuard 公钥：

```bash
# 查看本机公钥
cat /etc/wireguard/publickey

# 将公钥填入对端配置的 [Peer] 部分
```

#### 4. 启动隧道

```bash
# 启动 WireGuard
wg-quick up wg0

# 设置开机自启
systemctl enable wg-quick@wg0
```

### 脚本其他功能

```bash
# 仅生成密钥对
./wireguard-tunnel-setup.sh --gen-key-only

# 查看当前配置
./wireguard-tunnel-setup.sh --show-config

# 卸载配置
./wireguard-tunnel-setup.sh --uninstall
```

### 与 ShadowProxy 配合使用

在 shadowsocks-rust 配置中，`outbound_fwmark` 设置为 `255`（默认值），所有代理出站流量会被打上 fwmark=255 的标记。源端服务器的策略路由会将这些标记流量导入 WireGuard 隧道。

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