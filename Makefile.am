SUBDIRS = . doc tests

share_perl5dir = $(datarootdir)/perl5/Vyatta
share_perl5_logindir = $(datarootdir)/perl5/Vyatta/Login
etcdir = /etc
initddir = /etc/init.d
modprobedir = /etc/modprobe.d
modprobe_DATA = etc/modprobe.d/dummy.conf
modprobe_DATA += etc/modprobe.d/realtek.conf
templatedir = $(datadir)/vyatta-op/templates
tmplscriptdir = $(datadir)/tmplscripts
yangdir = /usr/share/configd/yang
vyatta_configdir = /opt/vyatta/etc/config
vyatta_securitydir = /opt/vyatta/etc/security/
overridedir = /etc/systemd/system
environmentdir = /etc/serial-getty/ttyS0
environment_DATA = etc/serial-getty/ttyS0/serial-getty.env
limitsdir = /etc/security/limits.d
limits_DATA = etc/security/limits.d/30-vyatta.conf
systemdconfdir = /etc/systemd/system.conf.d
systemdconf_DATA = etc/systemd/system.conf.d/30-vyatta.conf
dbussystemdconfdir = /etc/dbus-1/system.d
dbussystemdconf_DATA = etc/dbus-1/system.d/net.vyatta.eng.cpu.history.conf
techsupportdir = $(datadir)/vyatta-op/functions/tech-support.d

bin_PROGRAMS =
bin_SCRIPTS =
sbin_SCRIPTS =
sysconf_DATA =
initd_SCRIPTS =

kbdconfigddir = /etc/kbd/config.d
kbdconfigd_DATA = etc/kbd/config.d/vyatta

bin_SCRIPTS  += scripts/vyatta-block-device
bin_SCRIPTS  += scripts/vyatta-clear-block-device-op
bin_SCRIPTS  += scripts/vyatta-conf-sensors
bin_SCRIPTS  += scripts/vyatta-cpu-summary.pl
bin_SCRIPTS  += scripts/vyatta-gettime.pl
bin_SCRIPTS  += scripts/vyatta-monitor
bin_SCRIPTS  += scripts/vyatta-monitor-parse.pl
bin_SCRIPTS  += scripts/vyatta-show-block-device
bin_SCRIPTS  += scripts/vyatta-show-dmi
bin_SCRIPTS  += scripts/vyatta-show-fru
bin_SCRIPTS  += scripts/vyatta-show-licenses.pl
bin_SCRIPTS  += scripts/vyatta-show-sensors
bin_SCRIPTS  += scripts/vyatta-show-version
bin_SCRIPTS  += scripts/vyatta-shutdown.pl
bin_SCRIPTS  += scripts/yesno
bin_SCRIPTS  += scripts/yangop-get-fru
bin_SCRIPTS  += scripts/yangop-get-sensor
sbin_SCRIPTS += scripts/check_file_in_config_dir
sbin_SCRIPTS += scripts/vyatta-cpu-history-client
sbin_SCRIPTS += scripts/vyatta-cpu-history-daemon
sbin_SCRIPTS += scripts/system/vyatta_check_domainname.pl
sbin_SCRIPTS += scripts/system/vyatta_update_hosts.pl
sbin_SCRIPTS += scripts/system/vyatta_update_resolv.pl
sbin_SCRIPTS += scripts/system/vyatta_update_console.pl
sbin_SCRIPTS += scripts/vyatta-system-nameservers
sbin_SCRIPTS += scripts/restore-ipv6-address.pl
sbin_SCRIPTS += scripts/vyatta-ipv6-disable
sbin_SCRIPTS += scripts/check-ipv4-ipv6.pl
sbin_SCRIPTS += scripts/vyatta-update-arp-params
sbin_SCRIPTS += scripts/vyatta-pxe-boot
sbin_SCRIPTS += scripts/system-configure
sbin_SCRIPTS += scripts/system-postconfigure
sbin_SCRIPTS += scripts/system-preconfigure
sbin_SCRIPTS += scripts/clear-system-config
sbin_SCRIPTS += scripts/vyatta-delete-log-file
sbin_SCRIPTS += scripts/vyatta-show-log-file
sbin_SCRIPTS += scripts/show-log-parser
sbin_SCRIPTS += scripts/setup-package-repo
sbin_SCRIPTS += scripts/vyatta-platform
sbin_SCRIPTS += scripts/ip6_disable_redirects
sbin_SCRIPTS += scripts/ipv6-wait-for-dad
sbin_SCRIPTS += scripts/vyatta-platform-setup
sbin_SCRIPTS += scripts/vyatta_static_host_mapping

share_perl5_DATA = lib/Vyatta/File.pm
share_perl5_DATA += lib/Vyatta/ioctl.pm
share_perl5_DATA += lib/Vyatta/FeatureConfig.pm
share_perl5_DATA += lib/Vyatta/PlatformConfig.pm
share_perl5_DATA += lib/Vyatta/RestoreIPv6Addr.pm

sysconf_DATA += sysconf/level

vyatta_config_scriptsdir = /opt/vyatta/etc/config/scripts
vyatta_config_scripts_SCRIPTS = scripts/vyatta-postconfig-bootup.script

vyatta_preconfigddir = /opt/vyatta/preconfig.d
vyatta_preconfigd_SCRIPTS = preconfig.d/0400-bootif-hwaddr
vyatta_preconfigd_SCRIPTS += preconfig.d/0500-vyatta-config-url
vyatta_preconfigd_SCRIPTS += preconfig.d/1000-fix_permissions
vyatta_preconfigd_SCRIPTS += preconfig.d/1000-init-bootfile
vyatta_preconfigd_SCRIPTS += preconfig.d/5000-package-repository
vyatta_preconfigd_SCRIPTS += preconfig.d/5000-ipv6-service-class

vyatta_postconfigddir = /opt/vyatta/postconfig.d
vyatta_postconfigd_SCRIPTS = postconfig.d/vyatta-bootif-dhcp

sudoersddir = /etc/sudoers.d
sudoersd_DATA = etc/sudoers.d/0vyatta

sysctlddir = /etc/sysctl.d
sysctld_DATA = etc/sysctl.d/30-vyatta-router.conf

update_motddir = /etc/update-motd.d
update_motd_SCRIPTS = etc/update-motd.d/00-version

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(templatedir)
	cd templates && $(cpiop) $(DESTDIR)$(templatedir)
	mkdir -p $(DESTDIR)$(tmplscritdir)
	cd tmplscripts && $(cpiop) $(DESTDIR)$(tmplscriptdir)
	mkdir -p $(DESTDIR)$(yangdir)
	cd yang && $(cpiop) $(DESTDIR)$(yangdir)
	mkdir -p $(DESTDIR)$(overridedir)
	cd override && $(cpiop) $(DESTDIR)$(overridedir)
	mkdir -p $(DESTDIR)$(techsupportdir)
	cd scripts/tech-support && $(cpiop) $(DESTDIR)$(techsupportdir)

install-data-hook:
	chmod 0440 $(DESTDIR)$(sudoersddir)/0vyatta


check:
# Workaround vyatta python module packaging issue,
# which lets pylint3 fail. __init__.py is missing,
# causes import-error for vyatta module.
	mkdir -p scripts/vyatta
	touch scripts/vyatta/__init__.py
	ln -s /usr/lib/python3/dist-packages/vyatta/configd.py scripts/vyatta/configd.py
# End of workaround
	pylint3 -E 					\
		scripts/vyatta-conf-sensors 		\
		scripts/vyatta-cpu-history-client 	\
		scripts/vyatta-cpu-history-daemon 	\
		scripts/vyatta-show-sensors		\
		scripts/yangop-get-sensor
