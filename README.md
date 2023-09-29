ShadowProxy - OpenWrt LuCI for Shadowsocks-Rust
===

Introduce
---

It supports to configure shadowsocks-rust tproxy(redir) and dns acl on openwrt, with LuCI interface.

Wish it helps.

Dependency
---

1. `sslocal`, the executable shadowsocks-rust binary file is extracted from shadowsocks-rust releases. For convenient and security, the repo contains a `sslocal` file, which contains updated features for better network connection. If you have any security concerns, please use the official bin file instead.
2. `nftables` and `iptables`, now it supports only `nftables`, which requires less coding work...

Configuration
---

All configuration files are under `/etc/shadowproxy`. A `config-template.json` file is updated by the `/etc/init.d/shadowproxy` with uci configuration from `/etc/config/shadowproxy`.


TODO
---

- [ ] .github action to package ipk
- [ ] support plugins
- [ ] support iptables for openwrt under 22.03
- [ ] support x86_64-musl and gnu platforms
- [ ] support more shadowsocks-rust configurations

Q&A
---

1. Installed but not appears in browser
    `rm -rf /tmp/luci-*`
    In Chrome `Clear Browsering Data`
2. How to install without `ipk`
    Copy sslocal to `/usr/bin/sslocal`
    Copy `htdocs/*` to `/www/`
    Copy `root/*` to `/`
    `/etc/init.d/shadowproxy enable`
    reboot
3. First time configuration (bug to fix)
    The `/etc/init.d/shadowproxy` will config `dnsmasq` server automatically. If you did not set the correct server, you may not be able to reach network, because no dns server available. Configure your server and save apply.
4. Supported Devices
   - aarch64-musl (armv8)

