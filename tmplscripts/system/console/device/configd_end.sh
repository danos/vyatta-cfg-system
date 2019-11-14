#!/opt/vyatta/bin/cliexec
sh -c "
declare -a devices=( $VAR(@@) )
if [ "\${#devices[*]}" == "0" ]; then
    echo Warning: Access to system console is unconfigured
fi "
