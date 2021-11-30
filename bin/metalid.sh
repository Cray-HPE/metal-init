#!/bin/bash

set -e

echo = PIT Identification = COPY/CUT START =======================================
cat /etc/pit-release
csi version
rpm -qa | grep 'metal-'
rpm -q pit-init
rpm -qa | grep nexus
echo = PIT Identification = COPY/CUT END =========================================
