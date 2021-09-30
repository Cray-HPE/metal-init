#!/bin/bash
LOG_DIR=/var/log/metal/
trap 'echo See logs for contacted nodes in $LOG_DIR' EXIT INT HUP TERM
set -ux

bmc_username=${USERNAME:-$(whoami)}
if [[ $(hostname) == *-pit ]]; then
    host_bmc="$(hostname | cut -d '-' -f2,3)-mgmt"
else
    host_bmc="$(hostname)-mgmt"
fi
mkdir -pv $LOG_DIR

HPE_CONF="$(dirname $0)/$(basename $0 | cut -d '.' -f1 | sed 's/-/-hpe-/g').ini"

# Lay of the Land; rules to abide by for reusable code, and easy identification of problems from new eyeballs.
# - For anything vendor related, use a common acronym (e.g. GigaByte=gb Hewlett Packard Enterprise=hpe)
# - do not add "big" (functions longer than 25 lines, give or take a reasonably, contextually relevant few couple of lines)


function check_compatibility() {
    local vendor=${1:-''}
    case $vendor in
        *GIGABYTE*)
            echo "No BIOS Baseline for: $vendor" && return 1
            ;;
        *Marvell*|HP|HPE)
            :
            ;;
        *'Intel'*'Corporation'*)
            echo "No BIOS Baseline for: $vendor" && return 1
            ;;
        *)
            echo "Unknown/new/unfamiliar vendor: $vendor" && return 1
            ;;
    esac
}

# die.. (quit and write a message into standard error).
function die(){
    [ -n "$1" ] && echo >&2 "$1" && exit 1
}

# warn.. (print to stderr but do not exit).
function warn(){
    [ -n "$1" ] && echo >&2 "$1"
}

# Use IPMI_PASSWORD to align with ipmitools usage of the same environment variable as described in the Shasta documentation.
bmc_password=${IPMI_PASSWORD:-''}
[ -z "$bmc_password" ] && die 'Need IPMI_PASSWORD exported to the environment.'

function ilo_config() {
    check_compatibility HPE || warn -
    local respecs
    respecs=$(ilorest --nologo list $(cat $HPE_CONF | cut -d '=' -f1 | tr -s '\n' ' ') --selector=BIOS. | diff --side-by-side --left-column $HPE_CONF - | awk '{print $NF}' | grep '=' | cut -d '=' -f1 | tr -s '\n' '|' | sed 's/|$//g')
    [ -z "$respecs" ] && return 0
    eval ilorest --nologo set $(grep -E "($respecs)" $HPE_CONF | xargs -i echo \"{}\" | tr -s '\n' ' ') --selector=Bios. --commit
    ilorest --nologo pending
}

function ilo_verify() {
    check_compatibility HPE || warn -
    # Without set -e or set -x or set -? this conditional doesn't wait for the return from ilorest --nologo.
    set -e
    [ "$(cat $HPE_CONF)" = "$(ilorest --nologo list $(cat $HPE_CONF | cut -d '=' -f1 | tr -s '\n' ' ') --selector=BIOS.)" ]
    set +e
}

function run_ilo() {
    # This only runs on HPE hardware.
    local vendor='hpe'
    local hosts_file=/etc/dnsmasq.d/statics.conf
    local need_recon=()
    echo "The running host [$host_bmc] will have settings applied last."
    [ -f $hosts_file ] || hosts_file=/etc/hosts
    num_bmcs=$(grep -oP 'ncn-\w\d+-mgmt' $hosts_file | sort -u | wc -l)
    echo "Verifying $((${num_bmcs} - 1)) iLO/BMCs (non-compute nodes) match BIOS baseline spec."
    for ncn_bmc in $(grep -oP 'ncn-\w\d+-mgmt' $hosts_file | sort -u | grep -v ncn-m001-mgmt); do
        echo "================================"; printf "Checking ${ncn_bmc} ... "

        ilorest --nologo login ${ncn_bmc} -u ${bmc_username} -p ${bmc_password} >/dev/null
        if ilo_verify = "0" ; then
            echo "up-to-spec"
        else
            echo "differs from spec"
            need_recon+=( "$ncn_bmc" )
        fi
        ilorest --nologo logout 2>&1 >/dev/null
    done

    # if running in Jenkins or if -y was given just continue.
    if [[ -n "${CI:-}" ]]; then
        echo "${need_recon@#} of $(($num_bmcs - 1)) need BIOS Baseline applied ... proceeding [CI/automation environment detected]"
    elif [[ "${BIOS:-'no'}" = 'yes' ]] ; then
        echo "${#need_recon[@]} of $(($num_bmcs - 1)) need BIOS Baseline applied ... proceeding [-y provided on cmdline]."
    elif [[ "${CHECK:-'no'}" = 'yes' ]] ; then
        [ "${#need_recon[@]}" = '0' ] && return 0 || die "${#need_recon[@]} of $(($num_bmcs - 1)) need BIOS Baseline applied ... exiting."
    else
        read -r -p "${#need_recon[@]} of $(($num_bmcs - 1)) need BIOS Baseline applied ... proceed? [Y/n]:" response
        case "$response" in
            [yY][eE][sS]|[yY])
                :
                ;;
            *)
                echo 'exiting ...'
                return 0
                ;;
        esac
    fi
    for ncn_bmc in ${need_recon[@]}; do
        echo "================================"; printf "Configuring ${ncn_bmc} ... "
        ilorest --nologo login ${ncn_bmc} -u ${bmc_username} -p ${bmc_password} >/dev/null

        ilo_config 2>&1 >$LOG_DIR/${ncn_bmc}.log
        echo 'done'
    done

    echo "================================"; printf "Checking (self) ${host_bmc} ... "
    ilorest --nologo login -u ${bmc_username} -p ${bmc_password} >/dev/null
        if [ ilo_verify = "0" ] ; then
            echo "up-to-spec"
        else
            echo "differs from spec"
            ilo_config 2>&1 >$LOG_DIR/${ncn_bmc}.log
        fi
    ilorest --nologo logout 2>&1 >/dev/null
    echo "Settings will apply on the next (re)boot of each NCN: ${need_recon[@]}"
}

if [[ ${1:-} = '-y' ]]; then
    export BIOS=yes
elif [[ ${1:-} = '--check' ]]; then
    export CHECK=yes
fi
run_ilo
echo "Re-run this script with --check as the first and only argument to validate spec."
