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

#shellcheck disable=SC2086

set -eu

WEB_ROOT=/var/www

function call_bmc {
    local vendor
    local channel=1 # GB & HPE

    vendor="$(ipmitool fru | awk '/Board Mfg/ && !/Date/ {print $4}')"
    if [[ "$vendor" = *Intel* ]]; then
        channel=3
    fi

    [ -z "$IPMI_PASSWORD" ] && echo >&2 'Need IPMI_PASSWORD set in env (export IPMI_PASSWORD=password).' && return 1
    echo 'Attempting to set all known BMCs (from /etc/conman.conf) to dhcp mode'
    echo "current BMC count: $(grep -c mgmt /var/lib/misc/dnsmasq.leases)"
    (
    export username=root
    export IPMI_PASSWORD=$IPMI_PASSWORD
    grep mgmt /etc/conman.conf | grep -v m001 | awk '{print $3}' | cut -d ':' -f2 | tr -d \" | xargs -t -i ipmitool -I lanplus -U $username -E -H {} lan set $channel ipsrc dhcp
    ) >/var/log/metal-bmc-restore.$$.out 2>&1
    sleep 2 && echo "new BMC count: $(grep -c mgmt /var/lib/misc/dnsmasq.leases)"
}

# Finds latest of each artifact regardless of subdirectory.
k8s_initrd="$(find ${WEB_ROOT}/ephemeral/data/k8s -name "*initrd*" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
k8s_kernel="$(find ${WEB_ROOT}/ephemeral/data/k8s -name "*.kernel" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
k8s_squashfs="$(find ${WEB_ROOT}/ephemeral/data/k8s -name "*.squashfs" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
ceph_initrd="$(find ${WEB_ROOT}/ephemeral/data/ceph -name "*initrd*" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
ceph_kernel="$(find ${WEB_ROOT}/ephemeral/data/ceph -name "*.kernel" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
ceph_squashfs="$(find ${WEB_ROOT}/ephemeral/data/ceph -name "*.squashfs" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"

# RULE! The kernels MUST match; the initrds may be different.
if [[ "$(basename ${k8s_kernel} | cut -d '-' -f1,2)" != "$(basename ${ceph_kernel} | cut -d '-' -f1,2)" ]]; then
    echo 'Mismatching kernels! The discovered artifacts will deploy an undesirable stack.' >&2
fi

call_bmc || echo no BMC password set, using existing dnsmasq.leases

echo "$0 is creating boot directories for each NCN with a BMC that has a lease in /var/lib/misc/dnsmasq.leases"
echo "Nodes without boot directories will still boot the non-destructive iPXE binary."
#shellcheck disable=SC2013
for ncn in $(grep -Eo 'ncn-[mw]\w+' /var/lib/misc/dnsmasq.leases | sort -u); do
    mkdir -pv ${ncn} && pushd ${ncn}
    cp -pv /var/www/boot/script.ipxe .
    if [[ "$ncn" =~ 'ncn-w' ]]; then
        sed -i -E 's/rd.luks(=1)?\s/rd.luks=0 /g' script.ipxe
    fi
    ln -vsnf ..${k8s_kernel///var\/www} kernel
    ln -vsnf ..${k8s_initrd///var\/www} initrd.img.xz
    ln -vsnf ..${k8s_squashfs///var\/www} filesystem.squashfs
    popd
done
#shellcheck disable=SC2013
for ncn in $(grep -Eo 'ncn-s\w+' /var/lib/misc/dnsmasq.leases | sort -u); do
    mkdir -pv ${ncn} && pushd ${ncn}
    cp -pv /var/www/boot/script.ipxe .
    ln -vsnf ..${ceph_kernel///var\/www} kernel
    ln -vsnf ..${ceph_initrd///var\/www} initrd.img.xz
    ln -vsnf ..${ceph_squashfs///var\/www} filesystem.squashfs
    popd
done

if ! [ "$(pwd)" = $WEB_ROOT ]; then
    rsync -rltDvq --remove-source-files ncn-* $WEB_ROOT 2>/dev/null && rmdir ncn-* || echo >&2 'FATAL: No NCN BMCs found in /var/lib/misc/dnsmasq.leases'
fi

echo 'done'
