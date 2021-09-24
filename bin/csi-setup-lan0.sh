#!/bin/bash

set -eu
set +x
if [ $# -lt 2 ]; then
cat << EOM >&2
  usage: csi-setup-lan0.sh CIDR|IP/MASQ GATEWAY DEVICE DNS1 DNS2
  i.e.: csi-setup-lan0.sh 172.29.16.5/20 172.29.16.1 172.30.84.40 em1 [em2]
EOM
  exit 1
fi
cidr="$1" && shift
gateway="$1" && shift
dns="$1" && shift
addr="$(echo $cidr | cut -d '/' -f 1)"
mask="$(echo $cidr | cut -d '/' -f 2)"
sed -i 's/^IPADDR=.*/IPADDR="'"${addr}"'\/'"${mask}"'"/g' /etc/sysconfig/network/ifcfg-lan0
sed -i 's/^PREFIXLEN=.*/PREFIXLEN="'"${mask}"'"/g' /etc/sysconfig/network/ifcfg-lan0
sed -i 's/^BRIDGE_PORTS=.*/BRIDGE_PORTS="'"$*"'"/g' /etc/sysconfig/network/ifcfg-lan0
echo "default $gateway - -" >/etc/sysconfig/network/ifroute-lan0
sed -i 's/NETCONFIG_DNS_STATIC_SERVERS=.*/NETCONFIG_DNS_STATIC_SERVERS="'"${dns:-9.9.9.9}"'"/' /etc/sysconfig/network/config
netconfig update -f
wicked ifreload lan0
systemctl restart wickedd-nanny # Shake out daemon handling of new lan0 name.
rDNS_FQDN=$(nslookup $addr - $(tail -n 1 /etc/resolv.conf | awk '{print $NF}') | awk '{print $NF}')
rDNS=$(echo $rDNS_FQDN | cut -d '.' -f1)
hostnamectl set-hostname ${rDNS}-pit
echo
