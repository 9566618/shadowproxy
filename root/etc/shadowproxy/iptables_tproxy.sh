#!/bin/bash

if [[ -z "$1" ]]; then
  echo "Missing shadowproxy redir port, usage: $0 port"
  exit 0
fi

iptables-save | grep -v shadowproxy- | iptables-restore
ip6tables-save | grep -v shadowproxy- | ip6tables-restore

### IPv4 RULES

# Create chnip ipset
ipset create chnip hash:net family inet -exist
ipset restore < chnip

# Create gfwlist ipset
# ipset create gfwlist hash:ip family inet timeout 7200 -exist
# ipset create bypasslist hash:ip family inet timeout 7200 -exist

SHADOWPROXY_REDIR_IP=0.0.0.0
SHADOWPROXY_REDIR_PORT=$1

readonly IPV4_RESERVED_IPADDRS="\
0/8 \
10/8 \
100.64/10 \
127/8 \
169.254/16 \
172.16/12 \
192/24 \
192.0.2.0/24 \
192.88.99/24 \
198.18/15 \
192.168/16 \
198.51.100/24 \
203.0.113/24 \
224/4 \
240/4 \
255.255.255.255/32 \
"

## TCP+UDP
# Strategy Route
ip -4 rule del fwmark 0x01 table 803
ip -4 rule add fwmark 0x01 table 803
ip -4 route del local 0.0.0.0/0 dev lo table 803
ip -4 route add local 0.0.0.0/0 dev lo table 803

# TPROXY for LAN
iptables -t mangle -N shadowproxy-tproxy
# Skip LoopBack, Reserved
for addr in ${IPV4_RESERVED_IPADDRS}; do
   iptables -t mangle -A shadowproxy-tproxy -d "${addr}" -j RETURN
done

# UDP: Bypass CN IPs
iptables -t mangle -A shadowproxy-tproxy -m set --match-set chnip dst -p udp -j RETURN
# TCP: Bypass CN IPs
iptables -t mangle -A shadowproxy-tproxy -m set --match-set chnip dst -p tcp -j RETURN


# UDP: TPROXY UDP to 60080
iptables -t mangle -A shadowproxy-tproxy -p udp -j TPROXY --on-port ${SHADOWPROXY_REDIR_PORT} --tproxy-mark 0x01/0x01
# TCP: TPROXY TCP to 60080
iptables -t mangle -A shadowproxy-tproxy -p tcp -j TPROXY --on-port ${SHADOWPROXY_REDIR_PORT} --tproxy-mark 0x01/0x01


# TPROXY for Local
iptables -t mangle -N shadowproxy-tproxy-mark
# Skip LoopBack, Reserved
for addr in ${IPV4_RESERVED_IPADDRS}; do
   iptables -t mangle -A shadowproxy-tproxy-mark -d "${addr}" -j RETURN
done

# Bypass CN IPs
iptables -t mangle -A shadowproxy-tproxy-mark -m set --match-set chnip dst -j RETURN

# Bypass sslocal's outbound data
iptables -t mangle -A shadowproxy-tproxy-mark -m mark --mark 0xff/0xff -j RETURN
# UDP: Set MARK and reroute
iptables -t mangle -A shadowproxy-tproxy-mark -p udp -j MARK --set-xmark 0x01/0xffffffff
# TCP: Set MARK and reroute
iptables -t mangle -A shadowproxy-tproxy-mark -p tcp -j MARK --set-xmark 0x01/0xffffffff

# Apply TPROXY to LAN
iptables -t mangle -A PREROUTING -p udp -j shadowproxy-tproxy
iptables -t mangle -A PREROUTING -p tcp -j shadowproxy-tproxy
#iptables -t mangle -A PREROUTING -p udp -m addrtype ! --src-type LOCAL ! --dst-type LOCAL -j shadowproxy-tproxy
# Apply TPROXY for Local
iptables -t mangle -A OUTPUT -p udp -j shadowproxy-tproxy-mark
iptables -t mangle -A OUTPUT -p tcp -j shadowproxy-tproxy-mark
#iptables -t mangle -A OUTPUT -p udp -m addrtype --src-type LOCAL ! --dst-type LOCAL -j shadowproxy-tproxy-mark

# DIVERT rules
# For optimizing TCP
# iptables -t mangle -N shadowproxy-divert
# iptables -t mangle -A shadowproxy-divert -j MARK --set-mark 1
# iptables -t mangle -A shadowproxy-divert -j ACCEPT
# iptables -t mangle -I PREROUTING -p tcp -m socket -j shadowproxy-divert

### IPv6 RULES

# Create chnip6 ipset
ipset create chnip6 hash:net family inet6 -exist
ipset restore < chnip6

# Create gfwlist6 ipset
# ipset create gfwlist6 hash:ip family inet6 timeout 7200 -exist
# ipset create bypasslist6 hash:ip family inet6 timeout 7200 -exist

SHADOWPROXY6_REDIR_IP=::
SHADOWPROXY6_REDIR_PORT=$(expr $SHADOWPROXY_REDIR_PORT + 1)

readonly IPV6_RESERVED_IPADDRS="\
::/128 \
::1/128 \
::ffff:0:0/96 \
::ffff:0:0:0/96 \
64:ff9b::/96 \
100::/64 \
2001::/32 \
2001:20::/28 \
2001:db8::/32 \
2002::/16 \
fc00::/7 \
fe80::/10 \
ff00::/8 \
"

## TCP+UDP
# Strategy Route
ip -6 rule del fwmark 0x1 table 803
ip -6 rule add fwmark 0x1 table 803
ip -6 route del local ::/0 dev lo table 803
ip -6 route add local ::/0 dev lo table 803

# TPROXY for LAN
ip6tables -t mangle -N shadowproxy-tproxy
# Skip LoopBack, Reserved
for addr in ${IPV6_RESERVED_IPADDRS}; do
   ip6tables -t mangle -A shadowproxy-tproxy -d "${addr}" -j RETURN
done

# Bypass sslocal's outbound data
# ip6tables -t mangle -A shadowproxy-tproxy -m mark --mark 0xff/0xff -j RETURN
# UDP: Bypass CN IPs
ip6tables -t mangle -A shadowproxy-tproxy -m set --match-set chnip6 dst -p udp -j RETURN
# UDP: TPROXY UDP to 60081
ip6tables -t mangle -A shadowproxy-tproxy -p udp -j TPROXY --on-port ${SHADOWPROXY6_REDIR_PORT} --tproxy-mark 0x01/0x01
# TCP: Bypass CN IPs
ip6tables -t mangle -A shadowproxy-tproxy -m set --match-set chnip6 dst -p tcp -j RETURN
# TCP: TPROXY UDP to 60081
ip6tables -t mangle -A shadowproxy-tproxy -p tcp -j TPROXY --on-port ${SHADOWPROXY6_REDIR_PORT} --tproxy-mark 0x01/0x01

# TPROXY for Local
ip6tables -t mangle -N shadowproxy-tproxy-mark
# Skip LoopBack, Reserved
for addr in ${IPV6_RESERVED_IPADDRS}; do
   ip6tables -t mangle -A shadowproxy-tproxy-mark -d "${addr}" -j RETURN
done

# Bypass sslocal's outbound data
ip6tables -t mangle -A shadowproxy-tproxy-mark -m mark --mark 0xff/0xff -j RETURN
# Bypass CN IPs
ip6tables -t mangle -A shadowproxy-tproxy-mark -m set --match-set chnip6 dst -j RETURN
# Set MARK and reroute
ip6tables -t mangle -A shadowproxy-tproxy-mark -p udp -j MARK --set-xmark 0x01/0xffffffff
ip6tables -t mangle -A shadowproxy-tproxy-mark -p tcp -j MARK --set-xmark 0x01/0xffffffff

# Apply TPROXY to LAN
ip6tables -t mangle -A PREROUTING -p udp -j shadowproxy-tproxy
ip6tables -t mangle -A PREROUTING -p tcp -j shadowproxy-tproxy
# Apply TPROXY for Local
ip6tables -t mangle -A OUTPUT -p udp -j shadowproxy-tproxy-mark
ip6tables -t mangle -A OUTPUT -p tcp -j shadowproxy-tproxy-mark


# DIVERT rules
# For optimizing TCP
# ip6tables -t mangle -N shadowproxy-divert
# ip6tables -t mangle -A shadowproxy-divert -j MARK --set-mark 1
# ip6tables -t mangle -A shadowproxy-divert -j ACCEPT
