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

# usage: get-sqfs.sh 0.0.8
# usage: get-sqfs.sh 0.0.7
# usage: get-sqfs.sh f1e225a-1609179792335
# note: pairs great with set-sqfs-links.sh

id=$1
if [ -z $id ]; then
    echo >&2 'Missing image ID (e.g. X.Y.Z or COMMIT-TIMESTAMP)'
    exit 1
fi

if [ -z "${ARTIFACTORY_USER}" ] || [ -z "${ARTIFACTORY_TOKEN}" ]; then
    echo >&2 "ARTIFACTORY_USER and ARTIFACTORY_TOKEN must be defined for accessing csm-images in artifactory.algol60.net. One or both were empty/undefined."
    exit 1
fi

stream=unstable
if [[ "$id" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
    stream=stable
fi

mkdir -pv /var/www/ephemeral/data/ceph
pushd /var/www/ephemeral/data/ceph || return
echo Downloading storage-ceph artifacts ...
wget --progress=bar:force:noscroll -q --show-progress -r -N -l 1 --no-remove-listing -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -R index.html* -e robots=off https://$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN@artifactory.algol60.net/artifactory/csm-images/${stream}/storage-ceph/${id}/
for file in ${id}/storage-ceph*.squashfs; do
    [ ! -f $file ] && echo >&2 Failed to download SquashFS.
done 
for file in ${id}/initrd.img*; do
    [ ! -f $file ] && echo >&2 Failed to download initrd.img.xz.
done
for file in ${id}/*kernel; do
    [ ! -f $file ] && echo >&2 Failed to download the kernel.
done 
ls -l ${id}/
 
popd || exit
mkdir -pv /var/www/ephemeral/data/k8s
pushd /var/www/ephemeral/data/k8s || return
echo Downloading kubernetes artifacts ...
wget --progress=bar:force:noscroll -q --show-progress -r -N -l 1 --no-remove-listing -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -R index.html* -e robots=off https://$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN@artifactory.algol60.net/artifactory/csm-images/${stream}/kubernetes/${id}/
for file in ${id}/kubernetes*.squashfs; do
    [ ! -f $file ] && echo >&2 Failed to download SquashFS.
done 
for file in ${id}/initrd.img*; do
    [ ! -f $file ] && echo >&2 Failed to download initrd.img.xz.
done
for file in ${id}/*kernel; do
    [ ! -f $file ] && echo >&2 Failed to download the kernel.
done 
ls -l ${id}/ 
popd || exit
