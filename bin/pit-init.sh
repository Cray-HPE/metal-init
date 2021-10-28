#!/bin/bash
# Author: rustydb <doomslayer@hpe.com>
PITDATA=/var/www/ephemeral
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

export username=${username:-$(whoami)}
bmc_password=${IPMI_PASSWORD:-''}
[ -z "$bmc_password" ] && die 'Need IPMI_PASSWORD exported to the environment (optionally, "export username=myuser" as well otherwise $(whoami) is assumed.)'

if [ -z "$SYSTEM_NAME" ] ; then
    echo 'SYSTEM_NAME was not set; resolving automatically ... '
    # foo-ncn-m001-pit  ---> foo
    # foo-ncn-m001      ---> foo
    # ncn-m001          ---> ncn # <-- not ideal, but this won't be used on an NCN
    # pit               ---> pit # <-- not ideal, but generic enough
    export SYSTEM_NAME="$(hostname | cut -d '-' -f1)"
fi

if [ -e /dev/disk/by-label/PITDATA ]; then
    mount -v -L PITDATA
fi

PREP_DIR=/var/www/ephemeral/prep
CSI_CONF=$PREP_DIR/system_config.yaml
set -e
if [ ! -d $PREP_DIR ] ; then
    echo >&2 "Need $PREP_DIR; this needs to be created by hand if this is a first-time install."
    echo >&2 "See: https://github.com/Cray-HPE/docs-csm/blob/main/install/bootstrap_livecd_usb.md#configuration-payload"
    exit 1
elif [ ! -f $CSI_CONF ] ; then
    echo >&2 'CSI needs inputs; no $CSI_CONF file detected!'
    echo >&2 'See: https://github.com/Cray-HPE/docs-csm/blob/main/install/bootstrap_livecd_usb.md#generate-installation-files'
    exit 1
fi
echo 'Generating Configuration ...'
(
    pushd /var/www/ephemeral/prep
    rm -rf $SYSTEM_NAME && csi config init
    cp -pv $SYSTEM_NAME/pit-files/* /etc/sysconfig/network/
    cp -pv $SYSTEM_NAME/dnsmasq.d/* /etc/dnsmasq.d/
    cp -pv $SYSTEM_NAME/basecamp/data.json /var/www/ephemeral/configs/
    cp -pv $SYSTEM_NAME/conman.conf /etc
    popd
)

SHASTA_CFG_DIR=$PREP_DIR/site-init
if [ ! -d $SHASTA_CFG_DIR ] ; then
    echo >&2 "Need $SHASTA_CFG_DIR; this needs to be created by hand if this is a first-time install."
    echo >&2 "See: https://github.com/Cray-HPE/docs-csm/blob/main/install/prepare_site_init.md#create-and-initialize-site-init-directory"
    exit 1
fi
echo 'Patching CA into data.json (cloud-init)'
csi patch ca --cloud-init-seed-file $PITDATA/configs/data.json --customizations-file $PITDATA/prep/site-init/customizations.yaml --sealed-secret-key-file $PITDATA/prep/site-init/certs/sealed_secrets.key

echo 'Loading sysconfig (ifcfg files) ... '
echo >&2 'WARNING: SSH may disconnect if it was already setup'

set +e
wicked ifreload all
set -e

echo 'Restarting basecamp conman dnsmasq ... ' && systemctl restart basecamp conman dnsmasq
echo 'Restarting nexus ... ' && systemctl restart nexus

echo 'Pre-Install Toolkit has been initialized ... '
