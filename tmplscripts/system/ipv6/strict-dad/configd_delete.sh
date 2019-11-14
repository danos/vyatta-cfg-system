#!/bin/bash
echo 1 > /proc/sys/net/ipv6/conf/all/accept_dad
echo 1 > /proc/sys/net/ipv6/conf/default/accept_dad
for ifname in /sys/class/net/eth* /sys/class/net/dp* ; do
    if [ -d "$ifname" ]; then
        ifname=${ifname#/sys/class/net/}
	echo 1 > "/proc/sys/net/ipv6/conf/$ifname/accept_dad"
    fi
done
