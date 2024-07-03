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

set -euo pipefail

if [ $# -lt 1 ]; then
  cat << EOM >&2
  usage: csi-setup-hmn.sh CIDR VLAN_ID [parent]
  e.g.

  csi-setup-hmn.sh 10.254.1.1/17 4
  csi-setup-hmn.sh 10.254.1.1/17 4 em1
EOM
  exit 1
fi
cidr="${1:-}"
vlan="${2:-}"
parent="${3:-bond0}"

mask="${cidr#*/}"

if [[ ! $vlan =~ [0-9]+ ]] || [ ! "$vlan" -ge 1 ] || [ ! "$vlan" -le 4094 ]; then
  echo >&2 "Invalid ID for VLAN: $vlan"
  echo >&2 "VLAN must be an integer where 1 ≤ x ≤ 4094"
#  exit 1
fi

cat << EOF > /tmp/ifcfg-bond0.hmn0
NAME='HMN Bootstrap DHCP Subnet'

# Set static IP (becomes "preferred" if dhcp is enabled)
BOOTPROTO='static'
IPADDR='${cidr}'
PREFIXLEN='${mask}'

# CHANGE AT OWN RISK:
ETHERDEVICE='${parent}'

# DO NOT CHANGE THESE:
VLAN_PROTOCOL='ieee802-1Q'
VLAN='yes'
VLAN_ID=${vlan}
ONBOOT='yes'
STARTMODE='auto'
EOF

wicked ifreload bond0.hmn0
systemctl restart wickedd-nanny
