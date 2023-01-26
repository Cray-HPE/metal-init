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
#
# Author: rustydb <doomslayer@hpe.com>
set -e
ERROR=0

# These may already be set in the environment if pit-init is being invoked during
# a fresh install. If they are, then set them to their current value.
export PITDATA="${PITDATA:-}"
export SYSTEM_NAME="${SYSTEM_NAME:-}"

function die () {
    echo >&2 ${1:-'Fatal Error!'}
    exit 1
}

function error() {
    echo >&2 "ERROR: ${1}"
    ERROR=1
}

#######################################
# Checks if a node is running on Google by checking for /etc/google_system
# can be sourced from csm-common-library once that is live
# Globals:
#   None
# Arguments:
#   None
# Output:
#   None
#   Returns 0 if /etc/google_system exists, 1 if not
#######################################
function isgcp {
  # defaults to /etc/google_system, but can be overridden
  _isgcp_identifier="etc/google_system"

  # if the file exists, it is likely on GCP
  [ -e "${_isgcp_identifier}" ] && return 0

  # metal images can still be booted on GCP, so check if there are any disks vendored by Google
  # if not, we conclude that this is not GCP
  lsblk --noheadings -o vendor | grep -q Google
  return $?
}

function init {

    echo 'Exporting tokens'
    set -x
    export mtoken='ncn-m(?!001)\w+-mgmt'
    export stoken='ncn-s\w+-mgmt'
    export wtoken='ncn-w\w+-mgmt'
    set +x

    # Dump release and RPM info for admin/CI visibility.
    /root/bin/metalid.sh

    if [ -e /dev/disk/by-label/PITDATA ]; then
        set +e
        mount -a -v
        set -e
        PITDATA="$(lsblk -o MOUNTPOINT -nr /dev/disk/by-label/PITDATA)"
    else
        # PITDATA needs to exist before this script is called, because pit-init relies on items existing
        # within pitdata prior to running it.
        error "No DISK exists for PITDATA"
    fi

    export PREP_DIR=${PITDATA}/prep
    if [ ! -d "$PREP_DIR" ]; then
        error "$PREP_DIR does not exist! This needs to be created and populated with CSI input files before re-running this script"
    fi
    export DATA_DIR=${PITDATA}/data
    export CONF_DIR=${PITDATA}/configs

    # Create our base directories if they do not already exist.
    if [ ! -d $DATA_DIR ]; then
        mkdir -pv $DATA_DIR
    fi
    if [ ! -d $CONF_DIR ]; then
        mkdir -pv $CONF_DIR
    fi
}

function load_csi {

    local csi_conf=${PREP_DIR}/system_config.yaml

    if [ ! -f $csi_conf ] ; then
        # TODO: MTL-1695 Update this to point to the new example system_config.yaml file.
        error "CSI needs inputs; no $csi_conf file detected!"
        die 'See: https://github.com/Cray-HPE/docs-csm/blob/main/install/prepare_configuration_payload.md'
    fi

    echo 'Generating Configuration ...'
    pushd $PREP_DIR
    if [ -z "$SYSTEM_NAME" ]; then
        SYSTEM_NAME=$(awk /system-name/'{print $NF}' < system_config.yaml)
    fi
    [ -d $SYSTEM_NAME ] && mv $SYSTEM_NAME $SYSTEM_NAME-"$(date '+%Y%m%d%H%M%S')"
    csi config init
    cp -pv $SYSTEM_NAME/pit-files/* /etc/sysconfig/network/
    cp -pv $SYSTEM_NAME/dnsmasq.d/* /etc/dnsmasq.d/
    cp -pv $SYSTEM_NAME/basecamp/data.json /var/www/ephemeral/configs/
    cp -pv $SYSTEM_NAME/conman.conf /etc
    popd
}

function load_ntp {
    echo 'Setting up NTP ...'
    if /root/bin/configure-ntp.sh; then
        echo 'NTP has been configured'
    else
        error 'Failed to setup NTP'
    fi
}

function load_site_init {
    site_init=${PREP_DIR}/site-init
    local site_init_error=0
    local yq_error=0
    local yq_binary=/usr/bin/yq

    if [ -z "$SYSTEM_NAME" ]; then
        echo >&2 "SYSTEM_NAME was not set, this is required to resolve auto-generated customizations from 'csi config init'"
        return 1
    fi

    # Resolve CSM_PATH and the yq binary.
    if ! command -v $yq_binary >/dev/null ; then
        if [ -z ${CSM_PATH} ] ; then
            error "Can not find CSM tarball providing the yq binary, CSM_PATH is empty!"
            yq_error=1
        elif [ ! -d ${CSM_PATH} ] ; then
            error "Can not find CSM_PATH: $CSM_PATH ; no such directory"
            yq_error=1
        fi
        yq_binary="${CSM_PATH}/shasta-cfg/utils/bin/$(uname | awk '{print tolower($0)}')/yq"
        if [ ! -f ${yq_binary} ] ; then
            error "Can not find yq binary at $yq_binary"
            yq_error=1
        fi
    fi

    # Resolve site_init.
    if [ ! -d $site_init ] ; then
        error "Need $site_init; this needs to be created. Create this before re-running $0!"
        error "See: https://github.com/Cray-HPE/docs-csm/blob/main/install/prepare_site_init.md#create-and-initialize-site-init-directory"
        return 1
    fi

    # YQ Merge CSI Customizations.yaml into site-inits; merge the CA cert data.
    if [ $yq_error = 0 ] ; then
        echo 'Merging Generated IPs into customizations.yaml'
        "$yq_binary" merge -xP -i ${site_init}/customizations.yaml <($yq_binary prefix -P "${PREP_DIR}/${SYSTEM_NAME}/customizations.yaml" spec)
    else
        error 'yq is not available for merging generated IPs into customizations.yaml!'
    fi

    if [ $site_init_error = 0 ] ; then
        echo 'Patching CA into data.json (cloud-init)'
        csi patch ca --cloud-init-seed-file ${CONF_DIR}/data.json --customizations-file ${site_init}/customizations.yaml --sealed-secret-key-file ${site_init}/certs/sealed_secrets.key
        echo 'Basecamp will need to be restarted in order to pickup the new CA - pit-init will restart this shortly.'
    else
        error "site-init does not exist at the expected location: $site_init"
    fi
}

function reload_interfaces {
    echo 'Loading sysconfig (ifcfg files) ... '
    echo 'WARNING: SSH may disconnect if it was already setup'
    set +e
    # wicked will return exit codes if no-device is found, despite the interface actually working it can return a non-zero exit
    # for example if a vlan is loaded before the bond, it will (for a moment) indicate a failure.
    # This command will always work unless CSI generates ifcfg files incorrectly, in which case we need to fix/bug CSI.
    # In those events, a `systemctl restart wickedd-nanny` is required, as well as a `systemctl restart wicked`, but only
    # after the configuration has been corrected.
    wicked ifreload all
    set -e
}

function load_and_start_systemd {
    # nexus takes longer to start, this ensures we fail-quickly on basecamp, conman, or dnsmasq if nexus is started by itself.
    local services=(basecamp.service dnsmasq.service nexus.service grok-exporter.service prometheus.service grafana.service)
    if ! isgcp; then
        services+=(conman.service)
    fi
    services=($(printf '%s\n' "${services[@]}" | sort))
    local max_retries=5
    local error=0
    local verb
    echo "Starting [${#services[@]}] services ... some may take a few minutes."
    for service in "${services[@]}"; do
        retries=0
        verb=start
        systemctl stop $service
        systemctl enable $service >/dev/null 2>&1
        printf 'Starting %-30s ... ' $service
        while ! time systemctl $verb $service >/dev/null 2>&1 ; do
            if [[ $retries -ge $max_retries ]]; then
                error=1
                break
            fi
            verb=restart
            retries=$((retries + 1))
            sleep 1
        done
        if [ $error -ne 0 ]; then
            echo >&2 "FAILED - Run: journalctl -xeu $service"
            break
        else
            echo "DONE - Moving on ... "
        fi
    done
    if [ $error -ne 0 ]; then
        error "Failed to start all systemd services."
    fi
}

function main {
  # vshasta does not need certain parts of pit-init or are they incompatible with it
  if ! isgcp /etc/google_system; then
    load_csi
    reload_interfaces
    load_site_init
  fi
    load_and_start_systemd
    load_ntp
}

echo 'Initializing the Pre-Install Toolkit'
init
main
if [ $ERROR = 0 ]; then
    echo 'Pre-Install Toolkit has been initialized ...'
else
    echo >&2 'Pre-Install Toolkit failed to initialize ...'
    echo >&2 'Please inspect the above output for any and all errors before moving on with a CSM install.'
fi
