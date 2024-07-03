#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022-2024 Hewlett Packard Enterprise Development LP
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
set -euo pipefail

function err_exit() {
  echo "Error: $1" >&2
  exit 1
}

set +x
if [ $# -lt 5 ]; then
  cat << EOM >&2
  usage: csi-setup-lan0.sh SYSTEM_NAME CIDR GATEWAY DNS1 DEVICE1 [... DEVICE_N]
         csi-setup-lan0.sh SYSTEM_NAME CIDR GATEWAY 'DNS1 DNS2 DNSN' DEVICE1 [... DEVICE_N]

  e.g.

  csi-setup-lan0.sh eniac 10.100.254.5/24 10.100.254.1 "16.110.135.51,16.110.135.52" em1 em2
EOM
  exit 1
fi

system_name="${1:-}" && shift
cidr="${1:-}" && shift
gateway="${1:-}" && shift
dns="${1:-}" && shift
mask="${cidr#*/}"
bridge_ports="$*"

# https://en.wikipedia.org/wiki/Hostname
if [[ ${#system_name} -gt 253 ]]; then
  echo 'Error: $system_name must be less than or equal to 253 ASCII characters' 2>&1
  exit 1
fi
hostname_regex='^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$'
if [[ ! $system_name =~ $hostname_regex ]]; then
  echo >&2 "$system_name is not a valid hostname"
  echo >&2 "must match regex: $hostname_regex"
  exit 1
fi

cat << EOF > /etc/sysconfig/network/ifcfg-lan0
NAME='External Site-Link'

# Select the NIC(s) for direct, external access.
BRIDGE_PORTS='${bridge_ports}'

# Set static IP (becomes "preferred" if dhcp is enabled)
# NOTE: IPADDR's route will override DHCPs.
BOOTPROTO='static'
IPADDR='${cidr}'
PREFIXLEN='${mask}'

# DO NOT CHANGE THESE:
ONBOOT='yes'
STARTMODE='auto'
BRIDGE='yes'
BRIDGE_STP='no'
EOF

echo "default $gateway - -" > /etc/sysconfig/network/ifroute-lan0

echo "Updating DNS ... "
sed -i'.bak' 's/NETCONFIG_DNS_STATIC_SERVERS=.*/NETCONFIG_DNS_STATIC_SERVERS="'"${dns}"'"/' /etc/sysconfig/network/config
echo "Backed up /etc/sysconfig/network/config to /etc/sysconfig/network/config.bak"
netconfig update -f || err_exit "'netconfig update -f' failed"
echo 'Updated /etc/resolv.conf'

echo -n 'Reloading lan0 sysconfig ... '
wicked ifreload lan0 || err_exit "'wicked ifreload lan0' failed"
# Shake out daemon handling of new lan0 name.
systemctl restart wickedd-nanny || err_exit "'systemctl restart wickedd-nanny' failed."
echo 'Done'

echo -n 'Setting hostname ... '
hostnamectl set-hostname "${system_name}-pit" || err_exit "'hostnamectl set-hostname ${system_name}-pit' failed."
echo 'Done'
