#!/bin/bash
cidr=$(ip a s lan0 | awk '/inet/ && !/inet6/ {print $2}')
addr="$(echo $cidr | cut -d '/' -f 1)"
rDNS_FQDN=$(nslookup $addr - $(tail -n 1 /etc/resolv.conf | awk '{print $NF}') | awk '{print $NF}')
rDNS=$(echo $rDNS_FQDN | cut -d '.' -f1)
echo "Setting hostname to $rDNS"
hostnamectl set-hostname ${rDNS}-pit
