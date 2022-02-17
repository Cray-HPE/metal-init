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

# usage: get-sqfs.sh -k 0.0.8
# usage: get-sqfs.sh -s 0.0.7
# usage: get-sqfs.sh -k f1e225a-1609179792335
# note: pairs great with set-sqfs-links.sh

t=$1
id=$2
[ -z $2 ] && id=$1
[ -z $id ] && exit 1

case "${t}" in
    -s)
        dir='ceph'
        type='storage-ceph'
        ;;
    -k)
        dir='k8s'
        type='kubernetes'
        ;;
    *)
        dir='k8s'
        type='kubernetes'
        ;;
esac

stream=unstable
if [[ "$id" =~ [0-9]*\.[0-9]*\.[0-9]*$ ]]; then
    stream=stable
fi

mkdir -pv /var/www/ephemeral/data/${dir}
pushd /var/www/ephemeral/data/${dir}
wget --mirror -np -nH --cut-dirs=4 -A *.kernel,*initrd*,*.squashfs -nv https://artifactory.algol60.net/artifactory/csm-images/${stream}/${type}/${id}/
popd