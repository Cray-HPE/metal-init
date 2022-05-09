#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
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
wicked ifdown lan0 && wicked ifup lan0
systemctl restart wickedd-nanny # Shake out daemon handling of new lan0 name.
#shellcheck disable=SC2046
rDNS_FQDN=$(nslookup $addr - $(tail -n 1 /etc/resolv.conf | awk '{print $NF}') | awk '{print $NF}')
rDNS=$(echo $rDNS_FQDN | cut -d '.' -f1)
hostnamectl set-hostname ${rDNS}-pit
echo
