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

function err_exit() {
    echo "Error: $1" >&2
    exit 1
}

set +x
if [ $# -lt 5 ]; then
cat << EOM >&2
  usage: csi-setup-lan0.sh SYSTEM_NAME CIDR|IP/MASQ GATEWAY DNS1 DEVICE1 [DEVICE2 DEVICEN]
         csi-setup-lan0.sh SYSTEM_NAME CIDR|IP/MASQ GATEWAY 'DNS1 DNS2 DNSN' DEVICE1 [DEVICE2 DEVICEN]
  i.e.: csi-setup-lan0.sh your-system-name 172.29.16.5/20 172.29.16.1 172.30.84.40 em1 [em2]
EOM
  exit 1
fi

system_name="$1" && shift
cidr="$1" && shift
gateway="$1" && shift
dns="$1" && shift
addr="$(echo $cidr | cut -d '/' -f 1)"
mask="$(echo $cidr | cut -d '/' -f 2)"

# https://en.wikipedia.org/wiki/Hostname
if [[ ${#system_name} -gt 253 ]]; then
    echo "Error: \$system_name must be less than or equal to 253 ASCII characters" 2>&1
    exit 1
fi
hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
[[ $system_name =~ $hostname_regex ]] || err_exit "$system_name is not a valid hostname"

sed -i "s/^BOOTPROTO=.*/BOOTPROTO='static'/g" /etc/sysconfig/network/ifcfg-lan0
sed -i 's/^IPADDR=.*/IPADDR="'"${addr}"'\/'"${mask}"'"/g' /etc/sysconfig/network/ifcfg-lan0
sed -i 's/^PREFIXLEN=.*/PREFIXLEN="'"${mask}"'"/g' /etc/sysconfig/network/ifcfg-lan0
sed -i 's/^BRIDGE_PORTS=.*/BRIDGE_PORTS="'"$*"'"/g' /etc/sysconfig/network/ifcfg-lan0
echo "default $gateway - -" >/etc/sysconfig/network/ifroute-lan0
sed -i 's/NETCONFIG_DNS_STATIC_SERVERS=.*/NETCONFIG_DNS_STATIC_SERVERS="'"${dns:-9.9.9.9}"'"/' /etc/sysconfig/network/config

netconfig update -f || err_exit "netconfig update -f failed"
wicked ifdown lan0 || err_exit "wicked ifdown lan0 failed"
wicked ifup lan0 || err_exit "wicked ifup lan0 failed"
# Shake out daemon handling of new lan0 name.
systemctl restart wickedd-nanny || err_exit "systemctl restart wickedd-nanny failed"
hostnamectl set-hostname ${system_name}-pit || err_exit "hostnamectl set-hostname ${system_name}-pit failed"
echo
