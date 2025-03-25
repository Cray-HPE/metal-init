#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022, 2025 Hewlett Packard Enterprise Development LP
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

if [ $# -lt 3 ]; then
cat << EOM >&2
  usage: csi-pxe-hmn.sh ROUTER_IP DHCP_RANGE_START_IP DHCP_RANGE_END_IP [DHCP_LEASE_TTL]
  i.e.: csi-pxe-hmn.sh 10.254.1.1 10.254.2.1 10.254.127.254 10m
EOM
  exit 1
fi
router="$1"
range_start="$2"
range_end="$3"
lease_ttl="${4:-10m}"

cat << EOF > /etc/dnsmasq.d/HMN.conf
# HMN:
server=/hmn/
address=/hmn/
domain=hmn,${range_start},${range_end},local
interface-name=pit.hmn,bond0.hmn0
dhcp-option=interace:bond0.hmn0,option:domain-search,hmn
interface=bond0.hmn0
cname=packages.hmn,pit.hmn
cname=registry.hmn,pit.hmn
dhcp-option=interface:bond0.hmn0,option:dns-server,${router%/*}
dhcp-option=interface:bond0.hmn0,option:ntp-server,${router%/*}
dhcp-option=interface:bond0.hmn0,option:router,${router%/*}
dhcp-range=interface:bond0.hmn0,${range_start},${range_end},${lease_ttl}
EOF
systemctl restart dnsmasq
