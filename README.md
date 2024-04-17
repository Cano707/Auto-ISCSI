# Auto-ISCSI

*Auto-ISCSI* provides the possbility to add a systemd service, which automounts iscsi drives
to mount points matching the names of the drives. 

*NOTE:* It is not supposed to look pretty but work, since life is to short.

## Prerequirments

It is expected that the iscsi-client, namely `iscsiadm` and `lsscsi`, are installed and 
configured.

Further the targets must have been discovered beforehand.

## Overview

The systemd-service `mount_iscsi.service` ultimately runs the shell script `mount_iscsi.sh`.
The shell script logs into all available targets and mounts every target to a mount point
in `/mnt/<name>`, where `<name>` matches the corresponding part in:
```
iqn.2005-10.org.freenas.ctl:<name>.iscsi;/dev/sda
```

## Configuration

The configuration for `ExecStart` inside the service file needs to point to the `mount_iscsi.sh`
script. 

