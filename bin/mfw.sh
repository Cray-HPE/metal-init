#!/bin/bash
# mfw: "metal firmware"

if [ $# -lt 1 ]; then
cat << EOM >&2
  usage: mfw <filename|pattern>
  i.e.: mfw A43
  i.e.: mfw A43_1.30_07_18_2020.signed.flash
EOM
  exit 1
fi

fw=$1
fw_home=http://pit/fw/river/
username=${username:-admin}
password=${password:-password}
fw_file=$(find $fw_home -name $fw*)
[ -f $fw_file ] || echo >&2 "Failed to stat $fw_file" && exit 1
image="$fw_home/$(basename $fw_file)"

# FIXME: Remove '-k' for insecure.
curl -X POST -k -u $username:$password https://${fw_home}/redfish/v1/UpdateService/Actions/UpdateService.Simpleupdate/ -H Content-Type:application/json -d '{"TransferProtocol":"HTTP", "ImageURI":"'$image'"}'