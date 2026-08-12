#
# Copyright (C) 2016-2023 King <9566618@gmail.com>
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=shadowproxy
PKG_VERSION:=1.25.0
PKG_RELEASE:=1

PKG_LICENSE:=GPLv3
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=King <9566618@gmail.com>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-$(PKG_RELEASE)
PKG_HASH:=skip

# The package ships a prebuilt sslocal, so it is not architecture independent.
# Tagging it with the target's package architecture makes opkg refuse to install
# a mips build on an arm router, and gives every CI job a distinctly named ipk
# instead of all of them colliding on shadowproxy_<version>_all.ipk.
PKGARCH:=$(ARCH_PACKAGES)

PKG_LIBC:=musl

# $(ARCH) is "arm" for every 32-bit ARM subtarget, from ARMv4 (arm_fa526) up to
# ARMv7 (arm_cortex-a15_neon-vfpv4), so it cannot select the right binary on its
# own. $(ARCH_PACKAGES) carries the CPU type. Every OpenWrt arm_cortex-a*
# subtarget is an ARMv7-A core (or an ARMv8 core running 32-bit code, which is a
# superset), so they all run the armv7-unknown-linux-musleabihf build. The other
# arm subtargets -- arm1176jzf-s, mpcore, arm926ej-s, xscale, fa526 -- are ARMv6
# or older; no binary is bundled for them and Build/Compile fails loudly.
SS_ARCH:=$(ARCH)
ifeq ($(ARCH),arm)
  SS_ARCH:=$(if $(filter arm_cortex-a%,$(ARCH_PACKAGES)),armv7,$(ARCH))
endif

PKG_TARGET_FILE:=$(SS_ARCH)-$(PKG_LIBC)/sslocal

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=VPN
	TITLE:=Shadowsocks-Rust TProxy
	URL:=https://github.com/shadowsocks/shadowsocks-rust
	DEPENDS:=+kmod-nft-tproxy
endef

define Package/$(PKG_NAME)/description
	LuCI Support for shadowsocks-rust, and it automatically
	sets dns and nftables tproxy. It also supports ACL rules
	for controlling all net packets
endef

# Nothing is compiled here, but fail early and with a readable message when the
# target has no bundled binary, instead of erroring out inside INSTALL_BIN.
define Build/Compile
	@if [ ! -f "./bin/$(PKG_TARGET_FILE)" ]; then \
		echo "$(PKG_NAME): no bundled sslocal for ARCH=$(ARCH) ARCH_PACKAGES=$(ARCH_PACKAGES)"; \
		echo "$(PKG_NAME): expected ./bin/$(PKG_TARGET_FILE)"; \
		exit 1; \
	fi
	echo "$(PKG_NAME): using bundled ./bin/$(PKG_TARGET_FILE)"
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/
	cp -pR ./root/* $(1)/
	$(INSTALL_DIR) $(1)/www
	cp -pR ./htdocs/* $(1)/www
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./bin/$(PKG_TARGET_FILE) $(1)/usr/bin
endef

define Package/$(PKG_NAME)/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	killall -HUP rpcd 2>/dev/null
	exit 0
}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))