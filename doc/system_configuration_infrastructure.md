System Configuration Infrastructure
===================================

NOTE: This covers the system configuration infrastructure and has no direct
relationship with Vyatta Configuration system (configd).


system-preconfigure
-------------------

In the preconfigure phase the system has completed the live-boot and
live-config phases. The filesystem is properly mounted and the early boot
network (PXE, cloud-init DHCP) is available but this phase is executed prior
to the start of services like the dataplane, the routing stack or the Vyatta
Configuration system.

Scripts for this phase are found in the path `/opt/vyatta/preconfig.d` and
are executed in lexical sort order of their names.


system-postconfigure
--------------------

The postconfigure phase starts after the Vyatta Configuration system has been
initialized with the contents of /config/config.boot.

Examples for tasks executed during this phase:

 - restart of DHCP client for existing leases (from previous phases)
 - reading of hypervisor specific configuration phases

Scripts executed during this phase are searched for in the order of the
following path:

 1. `/opt/vyatta/postconfig.d` and are executed in lexical sort order
 2. `/opt/vyatta/etc/config/scripts/vyatta-postconfig-bootup.script`


Customer Extensions
-------------------

Customers are able to provide a custom post-configuration script in
`/config/scripts/vyatta-postconfig-bootup.script` either by manual copying
them or via the kernel cmdline parameter 'vyatta-config' (for more information
see the documentation at `vyatta-config.md`).

This script is executed on every boot after all other postconfigure scripts
completed. When adding another system image the script is taken over whenever
the existing configuration is preserved.
