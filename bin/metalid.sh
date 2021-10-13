#!/bin/bash

set -e

echo = PIT Identification = COPY/CUT START =======================================
cat /etc/pit-release
csi version
rpm -qa | grep 'metal-'
rpm -q pit-init
echo = PIT Identification = COPY/CUT END =========================================
