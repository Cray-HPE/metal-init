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

set -euo pipefail

WEB_ROOT=/var/www

function call_bmc {
    local actual_bmcs=0
    local expected_bmcs=0
    local vendor
    local channel=1 # GB & HPE

    expected_bmcs="$(grep -P 'host-record=ncn-\w\d+-mgmt' /etc/dnsmasq.d/statics.conf | grep -v m001 | wc -l)"
    vendor="$(ipmitool fru | awk '/Board Mfg/ && !/Date/ {print $4}')"
    if [[ "$vendor" = *Intel* ]]; then
        channel=3
    fi

    [ -z "$IPMI_PASSWORD" ] && echo >&2 'Need IPMI_PASSWORD set in env (export IPMI_PASSWORD=password).' && return 1
    echo 'Attempting to set all known BMCs (from /etc/conman.conf) to DHCP mode'
    echo "current BMC count: $(grep -c mgmt /var/lib/misc/dnsmasq.leases)"
    (
    export username=root
    export IPMI_PASSWORD=$IPMI_PASSWORD
    grep mgmt /etc/conman.conf | grep -v m001 | awk '{print $3}' | cut -d ':' -f2 | tr -d \" | xargs -t -i ipmitool -I lanplus -U $username -E -H {} lan set $channel ipsrc dhcp
    ) >/var/log/metal-bmc-restore.$$.out 2>&1
    function _actual_bmcs {
        grep -c mgmt /var/lib/misc/dnsmasq.leases
    }
    actual_bmcs="$(_actual_bmcs)"
    echo "Waiting on $expected_bmcs to request DHCP ... "
    while [ ! "$actual_bmcs" -eq "$expected_bmcs" ] ; do
        actual_bmcs="$(_actual_bmcs)"
        echo -ne "Current: $actual_bmcs\033[0K\r"
        sleep 1
    done
    echo "All [$expected_bmcs] expected BMCs have requested DHCP."
}

# Finds latest of each artifact regardless of subdirectory.
echo "Resolving images to boot ... "
k8s_initrd="$(find ${WEB_ROOT}/ephemeral/data/k8s -name "*initrd*" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
k8s_kernel="$(find ${WEB_ROOT}/ephemeral/data/k8s -name "*.kernel" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
k8s_squashfs="$(find ${WEB_ROOT}/ephemeral/data/k8s -name "*.squashfs" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
ceph_initrd="$(find ${WEB_ROOT}/ephemeral/data/ceph -name "*initrd*" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
ceph_kernel="$(find ${WEB_ROOT}/ephemeral/data/ceph -name "*.kernel" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"
ceph_squashfs="$(find ${WEB_ROOT}/ephemeral/data/ceph -name "*.squashfs" -printf '%T@ %p\n' | sort -n | tail -1 |  cut -f2- -d" ")"

test -z $k8s_initrd && echo "ERROR: k8s initrd not found in ${WEB_ROOT}/ephemeral/data/k8s" >&2 && exit 1
test -z $k8s_kernel && echo "ERROR: k8s kernel not found in ${WEB_ROOT}/ephemeral/data/k8s" >&2 && exit 1
test -z $k8s_squashfs && echo "ERROR: k8s squashfs not found in ${WEB_ROOT}/ephemeral/data/k8s" >&2 && exit 1

test -z $ceph_initrd && echo "ERROR: storage initrd not found in ${WEB_ROOT}/ephemeral/data/ceph" >&2 && exit 1
test -z $ceph_kernel && echo "ERROR: storage kernel not found in ${WEB_ROOT}/ephemeral/data/ceph" >&2 && exit 1
test -z $ceph_squashfs && echo "ERROR: storage squasfh not found in ${WEB_ROOT}/ephemeral/data/ceph" >&2 && exit 1
echo 'Images resolved'
echo -e "Kubernetes Boot Selection:\n\tkernel: $k8s_kernel\n\tinitrd: $k8s_initrd\n\tsquash: $k8s_squashfs"
echo -e "Storage Boot Selection:\n\tkernel: $ceph_kernel\n\tinitrd: $ceph_initrd\n\tsquash: $ceph_squashfs"

# RULE! The kernels MUST match; the initrds may be different.
if [[ "$(basename ${k8s_kernel} | cut -d '-' -f1,2)" != "$(basename ${ceph_kernel} | cut -d '-' -f1,2)" ]]; then
    echo 'Mismatching kernels! The discovered artifacts will deploy an undesirable stack.' >&2
fi

call_bmc || echo no BMC password set, using existing dnsmasq.leases

echo "$0 is creating boot directories for each NCN with a BMC that has a lease in /var/lib/misc/dnsmasq.leases"

echo -e "\tNOTE: Nodes without boot directories will still boot the non-destructive iPXE binary for bare-metal discovery usage."

if [ -n "${CSM_RELEASE:-}" ]; then
    if grep -q rd.live.dir /var/www/boot/script.ipxe; then
        sed -i -E 's/rd.live.dir=.* root/rd.live.dir='"$CSM_RELEASE"' root/g' /var/www/boot/script.ipxe
    else
        sed -i -E 's/live-sqfs-opts root/live-sqfs-opts rd.live.dir='"$CSM_RELEASE"' root/g' /var/www/boot/script.ipxe
    fi
    echo -e "\tImages will be stored on the NCN at /run/initramfs/live/$CSM_RELEASE/"
else
    if grep -q rd.live.dir /var/www/boot/script.ipxe; then
        sed -i -E 's/rd.live.dir=.* root/root/g' /var/www/boot/script.ipxe
    fi
    echo -e >&2 "\tWARNING: CSM_RELEASE was not set, images will be stored in their default location on the node(s) at /run/initramfs/live/LiveOS/"
fi

readarray -t NCNS_K8S < <(grep -Eo 'ncn-[mw]\w+' /var/lib/misc/dnsmasq.leases | sort -u)
if [ "${#NCNS_K8S[@]}" = 0 ]; then
    echo >&2 'No kubernetes NCN BMCs found in /var/lib/misc/dnsmasq.leases'
    exit 1
fi
for ncn in "${NCNS_K8S[@]}"; do
    mkdir -p ${ncn} && pushd ${ncn} >/dev/null
    cp -p /var/www/boot/script.ipxe .
    if [[ "$ncn" =~ 'ncn-w' ]]; then
        sed -i -E 's/rd.luks(=1)?\s/rd.luks=0 /g' script.ipxe
        sed -i -E '/ncn-params .*/ s/$/ split_lock_detect=off/' script.ipxe
    fi
    ln -snf ..${k8s_kernel///var\/www} kernel
    ln -snf ..${k8s_initrd///var\/www} initrd.img.xz
    ln -snf ..${k8s_squashfs///var\/www} rootfs
    popd >/dev/null
done
readarray -t NCNS_CEPH < <(grep -Eo 'ncn-s\w+' /var/lib/misc/dnsmasq.leases | sort -u)
if [ "${#NCNS_CEPH[@]}" = 0 ]; then
    echo >&2 'No storage NCN BMCs found in /var/lib/misc/dnsmasq.leases'
    exit 1
fi
for ncn in "${NCNS_CEPH[@]}"; do
    mkdir -p ${ncn} && pushd ${ncn} >/dev/null
    cp -p /var/www/boot/script.ipxe .
    ln -snf ..${ceph_kernel///var\/www} kernel
    ln -snf ..${ceph_initrd///var\/www} initrd.img.xz
    ln -snf ..${ceph_squashfs///var\/www} rootfs
    popd >/dev/null
done

if ! [ "$(pwd)" = $WEB_ROOT ]; then
    rsync -rltDvq --remove-source-files ncn-* $WEB_ROOT 2>/dev/null && rmdir ncn-*
fi

echo '/var/www is ready.'
