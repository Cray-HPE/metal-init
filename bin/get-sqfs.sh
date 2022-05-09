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

# usage: get-sqfs.sh 0.0.8
# usage: get-sqfs.sh 0.0.7
# usage: get-sqfs.sh f1e225a-1609179792335
# note: pairs great with set-sqfs-links.sh

id=$1
if [ -z $id ]; then
    echo >&2 'Missing image ID (e.g. X.Y.Z or COMMIT-TIMESTAMP)'
    exit 1
fi

stream=unstable
if [[ "$id" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
    stream=stable
fi

mkdir -pv /var/www/ephemeral/data/ceph
pushd /var/www/ephemeral/data/ceph
echo Downloading storage-ceph artifacts ...
wget --mirror -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -R index.html* -e robots=off -nv https://artifactory.algol60.net/artifactory/csm-images/${stream}/storage-ceph/${id}/
[ ! -f ${id}/storage-ceph*.squashfs ] && echo >&2 Failed to download SquashFS. 
[ ! -f ${id}/initrd.img.xz ] && echo >&2 Failed to download initrd.img.xz.
[ ! -f ${id}/*kernel ] && echo >&2 Failed to download the kernel. 
ls -l ${id}/ 
popd
mkdir -pv /var/www/ephemeral/data/k8s
pushd /var/www/ephemeral/data/k8s
echo Downloading kubernetes artifacts ...
wget --mirror -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -R index.html* -e robots=off -nv https://artifactory.algol60.net/artifactory/csm-images/${stream}/kubernetes/${id}/
[ ! -f ${id}/kubernetes*.squashfs ] && echo >&2 Failed to download SquashFS. 
[ ! -f ${id}/initrd.img.xz ] && echo >&2 Failed to download initrd.img.xz.
[ ! -f ${id}/*kernel ] && echo >&2 Failed to download the kernel.
ls -l ${id}/ 
popd
