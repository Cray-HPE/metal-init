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
#
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
#shellcheck disable=SC2061
fw_file=$(find $fw_home -name $fw*)
[ -f $fw_file ] || echo >&2 "Failed to stat $fw_file" && exit 1
image="$fw_home/$(basename $fw_file)"

# FIXME: Remove '-k' for insecure.
curl -X POST -k -u $username:$password https://${fw_home}/redfish/v1/UpdateService/Actions/UpdateService.Simpleupdate/ -H Content-Type:application/json -d '{"TransferProtocol":"HTTP", "ImageURI":"'$image'"}'
