#!/bin/bash

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