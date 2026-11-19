# Installs nulifyer-vpn's system half; karchy's PKGBUILD
# (packaging/pkgbuilds/nulifyer-vpn) runs `make DESTDIR=$pkgdir install`.
# Everything root runs lands in root-owned /usr, never in a home folder.

DESTDIR ?=
PREFIX ?= /usr
LIBDIR := $(PREFIX)/lib/nulifyer-vpn
.PHONY: install check

install:
	install -Dm755 bin/nulifyer-vpn bin/nulifyer-vpn-status -t $(DESTDIR)$(PREFIX)/bin
	install -Dm644 lib/common.sh -t $(DESTDIR)$(LIBDIR)
	install -Dm755 lib/control lib/policy lib/guard lib/configure -t $(DESTDIR)$(LIBDIR)
	install -Dm644 systemd/*.service systemd/*.path -t $(DESTDIR)$(PREFIX)/lib/systemd/system
	install -Dm644 tmpfiles/nulifyer-vpn.conf $(DESTDIR)$(PREFIX)/lib/tmpfiles.d/nulifyer-vpn.conf
	install -Dm755 networkmanager/90-nulifyer-vpn $(DESTDIR)$(PREFIX)/lib/NetworkManager/dispatcher.d/90-nulifyer-vpn
	install -d $(DESTDIR)$(PREFIX)/lib/NetworkManager/dispatcher.d/pre-up.d
	ln -sf ../90-nulifyer-vpn $(DESTDIR)$(PREFIX)/lib/NetworkManager/dispatcher.d/pre-up.d/90-nulifyer-vpn
	install -Dm644 polkit/org.nulifyer.vpn.policy -t $(DESTDIR)$(PREFIX)/share/polkit-1/actions
	install -Dm644 polkit/49-nulifyer-vpn.rules -t $(DESTDIR)$(PREFIX)/share/polkit-1/rules.d
	install -Dm644 examples/config $(DESTDIR)$(PREFIX)/share/nulifyer-vpn/config.example
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/nulifyer-vpn/LICENSE

check:
	shellcheck -x bin/nulifyer-vpn bin/nulifyer-vpn-status lib/common.sh lib/control lib/policy lib/guard networkmanager/90-nulifyer-vpn
	python3 -m py_compile lib/configure
