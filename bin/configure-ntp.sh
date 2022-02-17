#!/bin/bash

# MIT License
# 
# (C) Copyright [2020,2022] Hewlett Packard Enterprise Development LP
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

set -e

usage() {
  # Generates a usage line
  # Any line startng with with a #/ will show up in the usage line
  grep '^#/' "$0" | cut -c4-
}

# Show usage when --help is passed
expr "$*" : ".*--help" > /dev/null && usage && exit 0

# parse info from data.json until this can be templated in csi
UPSTREAM_NTP_POOLS=$(cat /var/www/ephemeral/configs/data.json | jq '.[]."user-data"."ntp"."pools"' | grep '"' | tr -d '"' | tr -d ',' | tr -d ' ' | sort | uniq)
UPSTREAM_NTP_SERVERS=$(cat /var/www/ephemeral/configs/data.json | jq '.[]."user-data"."ntp"."servers"' | grep '"' | tr -d '"' | tr -d ',' | tr -d ' ' | sort | uniq)
NTP_LOCAL_NETS=$(cat /var/www/ephemeral/configs/data.json | jq '.[]."user-data"."ntp"."allow"' | grep '"' | tr -d '"' | tr -d ',' | tr -d ' ' | sort | uniq)
NTP_PEERS=$(cat /var/www/ephemeral/configs/data.json | jq '.[]."user-data"."ntp"."peers"' | grep '"' | tr -d '"' | tr -d ',' | tr -d ' ' | sort | uniq \
            || cat /var/www/ephemeral/configs/data.json | jq | awk -F '"' '/ntp_peers/ {print $4}' \
            || echo -n '' )
NTP_LOCAL_NETS=$(cat /var/www/ephemeral/configs/data.json | jq '.[]."user-data"."ntp"."allow"' | grep '"' | tr -d '"' | tr -d ',' | tr -d ' ' | sort | uniq \
            || cat /var/www/ephemeral/configs/data.json | jq | awk -F '"' '/ntp_local_nets/ {print $4}' \
            || echo -n '' )
CHRONY_CONF=/etc/chrony.d/cray.conf

create_chrony_config() {
  # clear the file first, making it if needed
  true >"$CHRONY_CONF"

  if [[ -z $UPSTREAM_NTP_SERVERS ]]; then
    :
  else
    for s in $UPSTREAM_NTP_SERVERS
    do
      if [[ "$s" == "ncn-m001" ]]; then
        :
      else
        echo "server $s iburst trust" >>"$CHRONY_CONF"
      fi
    done
  fi

  if [[ -z $UPSTREAM_NTP_POOLS ]]; then
    :
  else
    for p in $UPSTREAM_NTP_POOLS
    do
      echo "pool $p iburst trust" >>"$CHRONY_CONF"
    done
  fi

  for net in ${NTP_LOCAL_NETS}
  do
     echo "allow $net" >>"$CHRONY_CONF"
  done

  # Step the clock in a stricter manner than the default *this is the value used in 1.3
  echo "makestep 0.1 3" >>"$CHRONY_CONF"
  echo "local stratum 3 orphan" >>"$CHRONY_CONF"
  echo "log measurements statistics tracking" >>"$CHRONY_CONF"
  echo "logchange 1.0" >>"$CHRONY_CONF"

  for n in $NTP_PEERS
  do
    # ncn-m001 (pit) should not be a peer to itself
    if [[ "$HOSTNAME" != "$n" ]] && [[ "$n" != "ncn-m001" ]]; then
      echo "peer $n minpoll -2 maxpoll 9 iburst" >>"$CHRONY_CONF"
    fi
  done
}

#/ Usage: set-ntp-config.sh [--help]
#/
#/    Configures NTP on the PIT
#/

if [[ -f /etc/chrony.d/pool.conf ]]; then
  rm -f /etc/chrony.d/pool.conf
fi
create_chrony_config
systemctl enable chronyd
systemctl restart chronyd
# Show the current time
echo "CURRENT TIME SETTINGS"
echo "rtc: $(hwclock)"
echo "sys: $(date "+%Y-%m-%d %H:%M:%S.%6N%z")"
# Ensure we use UTC
timedatectl set-timezone UTC
# bursting immediately after restarting the service can sometimes give a 503, even if the server is reachable.
# This just gives the service a little bit of time to settle
sleep 15
# quickly make (4 good measurements / 4 maximum)
chronyc burst 4/4
# wait a short bit to make sure the measurements happened
sleep 15
# then step the clock immediately if neeed
chronyc makestep
hwclock --systohc --utc
systemctl restart chronyd

echo "NEW TIME SETTINGS"
echo "rtc: $(hwclock)"
echo "sys: $(date "+%Y-%m-%d %H:%M:%S.%6N%z")"
