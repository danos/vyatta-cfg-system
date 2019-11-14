#!/bin/bash
/opt/vyatta/sbin/vyatta_update_resolv.pl "$@"
/opt/vyatta/sbin/vyatta_update_hosts.pl --no-restart-services "$@"
