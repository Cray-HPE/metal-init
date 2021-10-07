# LiveCD Scripts

The scripts located at `/root/bin` are bound to the LiveCD, these assist with environment setup
 for first or subsequent reuse of the LiveCD.

## BIOS / Bootstrap Helpers

These scripts control the BIOS of the CRAY non-compute-nodes for configuring plan-of-record BIOS (to the extent that it can be).

> `bios-baseline.sh`

The main run script, targets all known BMCs in `/etc/dnsmasq.d/statics.conf` and `/etc/hosts`.

This script can run on a non-compute-node or a pre-install-toolkit environment.

> `bios-hpe-baseline.ini`

The main configuration script. Anything in here must match what's in the target. These settings come
from: [docs-csm/background/ncn_bios.md](https://github.com/Cray-HPE/docs-csm/blob/59c66b326647eb03f1fe27f2d158260def921068/background/ncn_bios.md).

## CSI Scripts

These scripts pre-date the cray-site-init tool, they exist today to help offline or remote-environments
that can't bootstrap a USB with the files for `csi`. Example: When a remote ISO is attached to a BMC,
the administrator can leverage these scripts to quickly setup the LiveCD.

> `csi-setup-*.sh`

These scripts all setup the interfaces they correspond to. Each one will dump usage
when ran with no args.

- `csi-setup-bond0.sh` 
- `csi-setup-lan0.sh` 

> `csi-pxe-*.sh`

These scripts all setup DHCP/DNS over the interfaces they correspond to.

- `csi-pxe-bond0.sh` 

## Bootstrap / Devel. Scripts

> - `configure-ntp.sh` 

Sets up NTP server with a low stratum, this enables the LiveCD
to act as an NTP server for bootstrapping.

> `get-sqfs.sh` 

This retrieves artifacts based on ID and drops it into `/var/www/ephemeral/data/`.

`-k` to retrieve kubernetes
`-s` to retrieve ceph

Takes any ID, stable or unstable:

```bash
get-sqfs.sh 5388d52-1610557641786
get-sqfs.sh 1.2.3-23
get-sqfs.sh 1.2.3
```

> `set-sqfs-links.sh`

This does a few things:
1. It scans `/var/www/ephemeral/data` for all boot artifacts.
2. It parses `/var/lib/misc/dnsmasq.leases` for all static NCN nodes.
3. Any static NCNs found will get a directory created at `/var/www/ncn-${type}${index}`
4. Any static NCN will point to their respective image.
5. A default set of artifacts in `/var/www` for hardware discovery.

> If `-s` is passed to this script then the default links will point to storage.
