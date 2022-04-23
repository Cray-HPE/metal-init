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

# Author: rustydb <doomslayer@hpe.com>
set -e
ERROR=0

echo 'Initializing the Pre-Install Toolkit'
echo 'Exporting tokens'
set -x
export mtoken='ncn-m(?!001)\w+-mgmt'
export stoken='ncn-s\w+-mgmt'
export wtoken='ncn-w\w+-mgmt'
set +x

/root/bin/metalid.sh

function die () {
    echo >&2 ${1:-'Fatal Error!'}
    exit 1
}

function error() {
    echo >&2 "ERROR: "${1}""
    ERROR=1
}

export username=${username:-$(whoami)}
bmc_password=${IPMI_PASSWORD:-''}
[ -z "$bmc_password" ] && die 'Need IPMI_PASSWORD exported to the environment (optionally, "export username=myuser" as well otherwise $(whoami) is assumed.)'

if [ -z "$SYSTEM_NAME" ] ; then
    # There is no LAN at this point, so no rDNS can be done to resolve this.
    echo 'SYSTEM_NAME was not set; resolving automatically ... '
    # foo-ncn-m001-pit  ---> foo
    # foo-ncn-m001      ---> foo
    # ncn-m001          ---> ncn # <-- not ideal, but this won't be used on an NCN
    # pit               ---> pit # <-- not ideal, but generic enough
    export SYSTEM_NAME="$(hostname | cut -d '-' -f1)"
fi

if [ -e /dev/disk/by-label/PITDATA ]; then
    set +e
    mount -v -L PITDATA
    set -e
fi

# Create our base directories if they do not already exist.
PIT_DATA=/var/www/ephemeral
PREP_DIR=${PIT_DATA}/prep
DATA_DIR=${PIT_DATA}/data
CONF_DIR=${PIT_DATA}/configs
CSI_CONF=${PREP_DIR}/system_config.yaml
SITE_INIT=${PREP_DIR}/site-init
[ ! -d $PREP_DIR ] && mkdir -pv $PREP_DIR
[ ! -d $DATA_DIR ] && mkdir -pv $DATA_DIR
[ ! -d $CONF_DIR ] && mkdir -pv $CONF_DIR
if [ ! -f $CSI_CONF ] ; then
    # TODO: MTL-1695 Update this to point to the new example system_config.yaml file.
    error 'CSI needs inputs; no $CSI_CONF file detected!'
    die 'See: https://github.com/Cray-HPE/docs-csm/blob/main/install/prepare_configuration_payload.md'
fi

# Resolve SITE_INIT.
site_init_error=0
if [ ! -d $SITE_INIT ] ; then
    error "Need $SITE_INIT; this needs to be created before invoking $0!"
    error "See: https://github.com/Cray-HPE/docs-csm/blob/main/install/prepare_site_init.md#create-and-initialize-site-init-directory"
    site_init_error=1
fi

# Resolve CSM_PATH and the yq binary.
yq_error=0
YQ_BINARY=/usr/bin/yq
if ! command -v $YQ_BINARY >/dev/null ; then
    if [ -z ${CSM_PATH} ] ; then
        error "Can not find CSM tarball providing the yq binary, CSM_PATH is empty!"
        yq_error=1
    elif [ ! -d ${CSM_PATH} ] ; then
        error "Can not find CSM_PATH: $CSM_PATH ; no such directory"
        yq_error=1
    fi
    YQ_BINARY="${CSM_PATH}/shasta-cfg/utils/bin/$(uname | awk '{print tolower($0)}')/yq"
    if [ ! -f ${YQ_BINARY} ] ; then
        error "Can not find yq binary at $YQ_BINARY"
        yq_error=1
    fi
fi

echo 'Generating Configuration ...'
(
    pushd $PREP_DIR
    [ -d $SYSTEM_NAME ] && mv $SYSTEM_NAME $SYSTEM_NAME-$(date '+%Y%m%d%H%M%S')
    csi config init
    cp -pv $SYSTEM_NAME/pit-files/* /etc/sysconfig/network/
    cp -pv $SYSTEM_NAME/dnsmasq.d/* /etc/dnsmasq.d/
    cp -pv $SYSTEM_NAME/basecamp/data.json /var/www/ephemeral/configs/
    cp -pv $SYSTEM_NAME/conman.conf /etc
    popd
)
if [ $yq_error = 0 ] ; then
    echo 'Merging Generated IPs into customizations.yaml'
    "$YQ_BINARY" merge -xP -i ${SITE_INIT}/customizations.yaml <($YQ_BINARY prefix -P "${PREP_DIR}/${SYSTEM_NAME}/customizations.yaml" spec)
else
    error 'yq is not available for merging generated IPs into customizations.yaml!'
fi 
if [ $site_init_error = 0 ] ; then
    echo 'Patching CA into data.json (cloud-init)'
    csi patch ca --cloud-init-seed-file ${CONF_DIR}/data.json --customizations-file ${SITE_INIT}/customizations.yaml --sealed-secret-key-file ${SITE_INIT}/certs/sealed_secrets.key
else
    error "site-init does not exist at the expected location: $SITE_INIT"
fi

echo 'Loading sysconfig (ifcfg files) ... '
echo 'WARNING: SSH may disconnect if it was already setup'
set +e
wicked ifreload all
set -e

# nexus takes longer to start, this ensures we fail-quickly on basecamp, conman, or dnsmasq if nexus is started by itself.
systemctl enable basecamp conman dnsmasq nexus
echo 'Restarting basecamp conman dnsmasq ... ' && systemctl restart basecamp conman dnsmasq
echo 'Restarting nexus ... ' && systemctl restart nexus

if [ $ERROR = 0 ]; then
    echo 'Pre-Install Toolkit has been initialized ...'
else
    echo >&2 'Pre-Install Toolkit failed to initialize ...'
    echo >&2 'Please inspect the above output for any and all errors before moving on with a CSM install.'
fi
