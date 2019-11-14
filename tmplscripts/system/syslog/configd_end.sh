#!/bin/bash
if /opt/vyatta/sbin/vyatta_update_syslog.pl; then
    /usr/sbin/invoke-rc.d rsyslog restart
fi
