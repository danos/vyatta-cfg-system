#!/opt/vyatta/bin/cliexec
/opt/vyatta/sbin/vyatta-update-arp-params 'update' 'table-size' '$VAR(@)' 'ipv6'
