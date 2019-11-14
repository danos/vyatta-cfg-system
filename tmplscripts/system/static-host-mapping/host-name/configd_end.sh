#!/opt/vyatta/bin/cliexec
host_file=/etc/hosts
vrf_name=$VAR(../../../../routing-instance/@)
PREFIX=''
if [[ -n "$vrf_name" ]]; then
    vrf_dir=$vrf_name
    PREFIX="routing routing-instance $vrf_name"
    host_path=/run/dns/vrf/$vrf_name
    if [ ! -d $host_path ]; then mkdir -p $host_path ; fi
    host_file=$host_path/hosts
else
    vrf_dir='default'
    vrf_name=""
fi

if [[ -e ${host_file} ]]; then
    grep -q "$VAR(@) .*#vyatta entry" ${host_file}
    if [ $? -eq 0 ]; then
        sed -i '/ $VAR(@) .*#vyatta entry/d' ${host_file}
    fi
fi

touch ${host_file}

inet=$(cli-shell-api returnValue $PREFIX system static-host-mapping host-name $VAR(@) inet )
if [ -z $inet ]; then
    exit 0
fi
declare -a aliases=( $VAR(alias/@@) )
echo -e "$VAR(inet/@)\t $VAR(@) ${aliases[*]} \t #vyatta entry" >>${host_file} 
if /opt/vyatta/sbin/vyatta_update_syslog.pl; then
    systemctl restart rsyslog.service
fi
