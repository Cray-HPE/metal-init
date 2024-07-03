#!/bin/bash

# MIT License
#
# (C) Copyright [2022] Hewlett Packard Enterprise Development LP
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

if [ $# -lt 3 ]; then
  cat << EOM >&2
  usage: csi-setup-bond0.sh CIDR BOND_MEMBER [... BOND_MEMBER_N]

  e.g.

  csi-setup-bond0.sh 10.1.1.1/16 p801p1 p801p2
EOM
  exit 1
fi
cidr="${1:-}" && shift

mask="${cidr#*/}"

cat << EOF > /etc/sysconfig/network/ifcfg-bond0
NAME='Internal Interface'

# Set static IP (becomes "preferred" if dhcp is enabled)
BOOTPROTO='static'
IPADDR='${cidr}'
PREFIXLEN='${mask}'

# CHANGE AT OWN RISK:
BONDING_MODULE_OPTS='mode=802.3ad miimon=100 lacp_rate=fast xmit_hash_policy=layer2+3'

# DO NOT CHANGE THESE:
ONBOOT='yes'
STARTMODE='auto'
BONDING_MASTER='yes'

# BOND MEMBERS:
EOF

devs=("$@")
for i in "${!devs[@]}"; do
  echo "BONDING_SLAVE${i}='${devs[$i]}'" >> /etc/sysconfig/network/ifcfg-bond0
done

wicked ifreload bond0
systemctl restart wickedd-nanny

echo 'Done.'
cat << EOM >&2
If interface changes do not appear right away, check again in 5-10 seconds. Otherwise triage further with:

  wicked ifstatus --verbose bond0
  grep bond0 /var/log/messages*

EOM
