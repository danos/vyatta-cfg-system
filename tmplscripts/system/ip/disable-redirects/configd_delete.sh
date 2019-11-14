#!/bin/bash
sh -c "echo 1 > /proc/sys/net/ipv4/conf/all/send_redirects"
sh -c "echo 1 > /proc/sys/net/ipv4/conf/default/send_redirects"
