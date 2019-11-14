#!/bin/bash
sh -c "echo 1 > /proc/sys/net/ipv6/conf/all/forwarding"
cd /proc/sys/net/ipv6/conf
for i in * ; do
    if [[ "$i" == "default" ]] ||
	[[ "$i" == "all" ]] ||
	[[ ! -d "$i" ]]; then
	continue
    fi
    if [[ -e /var/run/vyatta/ipv6_no_fwd.$i ]]; then
	sh -c "echo 0 > $i/forwarding"
    fi
done
sh -c "echo 1 > /proc/sys/net/ipv6/conf/default/forwarding"
#
# If router advertisements were configured while global IPv6
# forwarding was disabled, we will need to restart the radvd daemon
# now, as the previous service start failed to start the process.
if [ ! -e /var/run/radvd/radvd.pid ] &&
    [ -s /etc/radvd.conf ]; then
    service radvd restart
fi
