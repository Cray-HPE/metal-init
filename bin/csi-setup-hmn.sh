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

set -eu
if [ $# -lt 1 ]; then
cat << EOM >&2
  usage: csi-setup-hmn.sh CIDR|IP/MASQ VLAN_ID
  i.e.: csi-setup-hmn.sh 10.254.1.1/17 4
EOM
  exit 1
fi
cidr="$1"
addr="$(echo $cidr | cut -d '/' -f 1)"
mask="$(echo $cidr | cut -d '/' -f 2)"
vlan="$(echo $cidr | cut -d '/' -f 3)"

cat << EOF >/tmp/ifcfg-bond0.hmn0
NAME='HMN Bootstrap DHCP Subnet'

# Set static IP (becomes "preferred" if dhcp is enabled)
BOOTPROTO='static'
IPADDR='${addr}/${mask}'
PREFIXLEN='${mask}'

# CHANGE AT OWN RISK:
ETHERDEVICE='bond0'

# DO NOT CHANGE THESE:
VLAN_PROTOCOL='ieee802-1Q'
VLAN='yes'
VLAN_ID=${vlan}
ONBOOT='yes'
STARTMODE='auto'
EOF

wicked ifreload bond0.hmn0
systemctl restart wickedd-nanny
