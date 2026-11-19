# Installs karchy-vpn's system half; karchy's PKGBUILD
# (packaging/pkgbuilds/karchy-vpn) runs `make DESTDIR=$pkgdir install`.
# Everything root runs lands in root-owned /usr, never in a home folder.

DESTDIR ?=
PREFIX ?= /usr
LIBDIR := $(PREFIX)/lib/karchy-vpn
.PHONY: install check

install:
	install -Dm755 bin/karchy-vpn bin/karchy-vpn-status -t $(DESTDIR)$(PREFIX)/bin
	install -Dm644 lib/common.sh -t $(DESTDIR)$(LIBDIR)
	install -Dm755 lib/control lib/policy lib/guard lib/configure -t $(DESTDIR)$(LIBDIR)
	install -Dm644 systemd/*.service systemd/*.path -t $(DESTDIR)$(PREFIX)/lib/systemd/system
	install -Dm644 tmpfiles/karchy-vpn.conf $(DESTDIR)$(PREFIX)/lib/tmpfiles.d/karchy-vpn.conf
	install -Dm755 networkmanager/90-karchy-vpn $(DESTDIR)$(PREFIX)/lib/NetworkManager/dispatcher.d/90-karchy-vpn
	install -d $(DESTDIR)$(PREFIX)/lib/NetworkManager/dispatcher.d/pre-up.d
	ln -sf ../90-karchy-vpn $(DESTDIR)$(PREFIX)/lib/NetworkManager/dispatcher.d/pre-up.d/90-karchy-vpn
	install -Dm644 polkit/org.karchy.vpn.policy -t $(DESTDIR)$(PREFIX)/share/polkit-1/actions
	install -Dm644 polkit/50-karchy-vpn.rules -t $(DESTDIR)$(PREFIX)/share/polkit-1/rules.d
	install -Dm644 examples/config $(DESTDIR)$(PREFIX)/share/karchy-vpn/config.example
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/karchy-vpn/LICENSE

check:
	shellcheck -x bin/karchy-vpn bin/karchy-vpn-status lib/common.sh lib/control lib/policy lib/guard networkmanager/90-karchy-vpn
	python3 -m py_compile lib/configure
