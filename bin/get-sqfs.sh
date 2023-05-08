#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022-2023 Hewlett Packard Enterprise Development LP
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

base_url=artifactory.algol60.net/artifactory/csm-images

function usage {
cat << 'EOF'
usage:

# Pull 0.0.8 Kubernetes and Storage-CEPH
get-sqfs.sh 0.0.8

# Pull f1e225a-1609179792335 Kubernetes and Storage-CEPH
get-sqfs.sh f1e225a-1609179792335

# Pull 0.2.3 Kubernetes and 0.4.3 Storage-CEPH
get-sqfs.sh -k 0.2.3 -s 0.4.3

# Pull only 0.4.3 Storage-CEPH
get-sqfs.sh -s 0.4.3

# Pull a pre-install-toolkit ISO
get-sqfs.sh -p 0.4.3

# Pull using a proxy to download Kubernetes and Storage-CEPH
get-sqfs.sh -P https://example.proxy.net:443 0.4.3

# Download to a local directory
get-sqfs.sh -P https://example.proxy.net:443 0.4.3 -d /tmp

EOF
}

if [ -z "${ARTIFACTORY_USER}" ] || [ -z "${ARTIFACTORY_TOKEN}" ]; then
    echo >&2 "ARTIFACTORY_USER and ARTIFACTORY_TOKEN must be defined"
    echo >&2 "for accessing csm-images in artifactory.algol60.net."
    echo >&2 "One or both were empty/undefined."
    exit 1
fi

ARCH=$(uname -m)
DEST="/var/www/ephemeral/data"
use_proxy=no
http_proxy='null'
while getopts ":k:H:p:s:a:P:d:" o; do
    case "${o}" in
        k)
            KUBERNETES_ID=${OPTARG}
            bucket='kubernetes'
            ;;
        H)
            HYPERVISOR_ID=${OPTARG}
            bucket='hypervisor'
            ;;
        p)
            PRE_INSTALL_TOOLKIT_ID=${OPTARG}
            bucket='pre-install-toolkit'
            ;;
        s)
            STORAGE_CEPH_ID=${OPTARG}
            bucket='storage-ceph'
            ;;
        a)
            ARCH=${OPTARG}
            ;;
        P)
            http_proxy=${OPTARG}
            use_proxy=yes
            ;;
        d)
            DEST=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

# By default, if an ID is given without any flags always download the NCN images (kubernetes + storage-ceph).
if [ -z ${KUBERNETES_ID} ] && [ -z ${STORAGE_CEPH_ID} ] && [ -z ${HYPERVISOR_ID} ] && [ -z ${PRE_INSTALL_TOOLKIT_ID} ]; then
    if [ -z "${*}" ]; then
        echo >&2 'Missing image ID (e.g. X.Y.Z or COMMIT-TIMESTAMP)'
        exit 1
    fi
    echo 'Assuming given ID is for Kubernetes and Storage-CEPH'
    KUBERNETES_ID="${*}"
    STORAGE_CEPH_ID="${*}"
fi

if [ -n "${STORAGE_CEPH_ID}" ]; then
    if [ -z "${bucket}" ]; then
        bucket=storage-ceph
    fi

    stream=unstable
    if [[ "$STORAGE_CEPH_ID" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
        stream=stable
    fi

    artifactory_url=https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@${base_url}/${stream}/${bucket}
    mkdir -pv ${DEST}/ceph
    pushd ${DEST}/ceph || return
    echo Downloading ${bucket} artifacts ...
    wget --progress=bar:force:noscroll -e use_proxy=${use_proxy} -e https_proxy=${http_proxy} -e http_proxy=${http_proxy} -q --show-progress -r -N -l 1 --no-remove-listing -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -R index.html* -e robots=off "${artifactory_url}/${STORAGE_CEPH_ID}/"
    for file in ${STORAGE_CEPH_ID}/${bucket}*.squashfs; do
        [ ! -f $file ] && echo >&2 Failed to download SquashFS.
    done
    for file in ${STORAGE_CEPH_ID}/initrd.img*; do
        [ ! -f $file ] && echo >&2 Failed to download initrd.img.xz.
    done
    for file in ${STORAGE_CEPH_ID}/*kernel; do
        [ ! -f $file ] && echo >&2 Failed to download the kernel.
    done
    ls -l ${STORAGE_CEPH_ID}/
    popd || exit
    unset bucket
fi

if [ -n "${HYPERVISOR_ID}" ]; then
    if [ -z "${bucket}" ]; then
        bucket=hypervisor
    fi

    stream=unstable
    if [[ "$HYPERVISOR_ID" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
        stream=stable
    fi

    artifactory_url=https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@${base_url}/${stream}/${bucket}
    mkdir -pv ${DEST}/${bucket}
    pushd ${DEST}/${bucket} || return
    echo Downloading ${bucket} artifacts ...
    wget --progress=bar:force:noscroll -e use_proxy=${use_proxy} -e https_proxy=${http_proxy} -e http_proxy=${http_proxy} -q --show-progress -r -N -l 1 --no-remove-listing -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs,*.iso -R index.html* -e robots=off "${artifactory_url}/${HYPERVISOR_ID}/"
    for file in ${HYPERVISOR_ID}/${bucket}*.iso; do
        [ ! -f $file ] && echo >&2 Failed to download ISO.
    done
    for file in ${HYPERVISOR_ID}/${bucket}*.squashfs; do
        [ ! -f $file ] && echo >&2 Failed to download SquashFS.
    done
    for file in ${HYPERVISOR_ID}/initrd.img*; do
        [ ! -f $file ] && echo >&2 Failed to download initrd.img.xz.
    done
    for file in ${HYPERVISOR_ID}/*kernel; do
        [ ! -f $file ] && echo >&2 Failed to download the kernel.
    done
    ls -l ${HYPERVISOR_ID}/
    popd || exit
    unset bucket
fi

if [ -n "${KUBERNETES_ID}" ]; then
    if [ -z "${bucket}" ]; then
        bucket=kubernetes
    fi

    stream=unstable
    if [[ "$KUBERNETES_ID" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
        stream=stable
    fi

    artifactory_url=https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@${base_url}/${stream}/${bucket}
    mkdir -pv ${DEST}/k8s
    pushd ${DEST}/k8s || return
    echo Downloading ${bucket} artifacts ...
    wget --progress=bar:force:noscroll -e use_proxy=${use_proxy} -e https_proxy=${http_proxy} -e http_proxy=${http_proxy} -q --show-progress -r -N -l 1 --no-remove-listing -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -R index.html* -e robots=off "${artifactory_url}/${KUBERNETES_ID}/"
    for file in ${KUBERNETES_ID}/${bucket}*.squashfs; do
        [ ! -f $file ] && echo >&2 Failed to download SquashFS.
    done
    for file in ${KUBERNETES_ID}/initrd.img*; do
        [ ! -f $file ] && echo >&2 Failed to download initrd.img.xz.
    done
    for file in ${KUBERNETES_ID}/*kernel; do
        [ ! -f $file ] && echo >&2 Failed to download the kernel.
    done
    ls -l ${KUBERNETES_ID}/
    popd || exit
    unset bucket
fi

if [ -n "${PRE_INSTALL_TOOLKIT_ID}" ]; then
    if [ -z "${bucket}" ]; then
        bucket=pre-install-toolkit
    fi

    stream=unstable
    if [[ "$PRE_INSTALL_TOOLKIT_ID" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
        stream=stable
    fi

    artifactory_url=https://${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}@${base_url}/${stream}/${bucket}
    pushd ${DEST} || return
    echo "Downloading ${bucket} ISO with ID: ${PRE_INSTALL_TOOLKIT_ID}"
    if [ "${use_proxy}" = 'yes' ]; then
        curl --proxy ${http_proxy} -C - -f -O "${artifactory_url}/${PRE_INSTALL_TOOLKIT_ID}/${bucket}-${PRE_INSTALL_TOOLKIT_ID}-${ARCH}.iso"
    else
        curl -C - -f -O "${artifactory_url}/${PRE_INSTALL_TOOLKIT_ID}/${bucket}-${PRE_INSTALL_TOOLKIT_ID}-${ARCH}.iso"
    fi
    [ ! -f ${bucket}-${PRE_INSTALL_TOOLKIT_ID}-${ARCH}.iso ] && echo >&2 "Failed to download ${bucket}-${PRE_INSTALL_TOOLKIT_ID}-${ARCH}.iso"
    echo "Downloaded ISO to $(pwd)/${bucket}-${PRE_INSTALL_TOOLKIT_ID}-${ARCH}.iso"
    popd || exit
fi
