#!/bin/bash
sh -c "echo 0 > /proc/sys/net/ipv6/conf/all/forwarding"
sh -c "echo 0 > /proc/sys/net/ipv6/conf/default/forwarding"
