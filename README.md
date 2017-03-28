# FreeNAS Scripts
Handy shell scripts for use on FreeNAS servers

These are my versions of the useful scripts available at the ["Scripts to report SMART, ZPool and UPS status, HDD/CPU T°, HDD identification and backup the config"](https://forums.freenas.org/index.php?threads/scripts-to-report-smart-zpool-and-ups-status-hdd-cpu-t%C2%B0-hdd-identification-and-backup-the-config.27365/) thread on the FreeNAS forum. The original author is FreeNAS forum member BiduleOhm, with others contributing suggestions and code changes. I have modified the syntax and made minor changes in formatting and spacing of the generated reports.

I used the excellent shell script static analysis tool at https://www.shellcheck.net to insure that all of the code is POSIX-compliant and free of issues. But this doesn't mean you won't find any errors.  ☺️
***
# smart_report.sh

Generates and emails you a status report with detailed SMART information about your system's drives.

By default, my version of this script uses a function I wrote which uses smartctl's scan list to obtain the SMART-enabled drives on the system, but you have the option of using either a hard-coded list or a sysctl-based method instead, if you so choose. This version allows for serial numbers up to 18 characters in length, where the original only supported 15. It also selects the "Device Model" as the drive 'brand' if the "Model Family" SMART attribute is unavailable.

You will need to edit the script and enter your email address before using it.
***
# zpool_report.sh

Generates and emails you a status report about your system's pools.

You will need to edit the script and enter your email address before using it.
***
# ups_report.sh
Generates and emails you a status report about your UPS.

You will need to edit the script and enter your email address before using it. You may also have the report include all of the available UPSC variables by setting the `senddetail` variable to a value greater than zero.
***
# save_config.sh

Saves your FreeNAS system configuration file to a dataset you specify. Supports both FreeNAS 9.x and the newer Corral version. The backup filenames are formed from the hostname, complete FreeNAS version, and date, in this format: _hostname-freenas_version-date.db_. Here is an example from a recent backup on my server named _boomer_:

```
boomer-FreeNAS-9.10.2-U2-e1497f2-20170315224905.db
```

Edit this script and specify the target dataset where you want the backup files copied.

Optional features:
* Specify your email address to receive notification messages whenever the script executes.
* Specify your ESXi short hostname to backup the ESXi server configuration file. These backup filenames are formed from the hostname and date in this format: _hostname-configBundle-date.tgz_. Here is an example from a recent backup on my server named _felix_, on which _boomer_ is a guest:

  ```
  felix-configBundle-20170315224905.tgz
  ```
***
# set_hdd_erc.sh

Sets the Error Recovery Control (aka SCTERC or TLER) read and write values on your system's hard drives. What is this? There is a good discussion in the ["Checking for TLER, ERC, etc. support on a drive"](https://forums.freenas.org/index.php?threads/checking-for-tler-erc-etc-support-on-a-drive.27126/) thread on the FreeNAS forum, and you can find more gory details in [this FAQ](https://www.smartmontools.org/wiki/FAQ#WhatiserrorrecoverycontrolERCandwhyitisimportanttoenableitfortheSATAdisksinRAID) at the [smartmontools.org](https://www.smartmontools.org) website. This key quote from the FAQ sums up why you want to set this up on your FreeNAS servers:

>"It is best for ERC to be "enabled" when in a RAID array to prevent the recovery time from a disk read or write error from exceeding the RAID implementation's timeout threshold. If a drive times out, the hard disk will need to be manually re-added to the array, requiring a re-build and re-synchronization of the hard disk. Limiting the drives recovery timeout helps for improved error handling in the hardware or software RAID environments."

By default, the script sets both the read and write timeout value to 7 seconds. You can change either or both of these values to better suit your environment.

Some hard drives retain these values when powered down, but some do not - including the HGST 7K4000 drives I use in one of my systems. For this reason, I configure my FreeNAS servers to run `set_hdd_src.sh` as a post-init startup script.
***
# get_hdd_temp.sh

Displays the current temperature of your system's CPUs and drives. Drive output includes: the device ID, temperature (in Centigrade), drive model/brand, and serial number. Here is sample output from one of my systems:

```
=== CPU (4) ===
CPU 0: 38C
CPU 1: 38C
CPU 2: 38C
CPU 3: 38C

=== DRIVES ===
da1:  32C Hitachi/HGST Ultrastar 7K4000 PK999999999999
da2:  34C Hitachi/HGST Ultrastar 7K4000 PK999999999999
da3:  33C Hitachi/HGST Ultrastar 7K4000 PK999999999999
da4:  32C Hitachi/HGST Ultrastar 7K4000 PK999999999999
da5:  32C Hitachi/HGST Ultrastar 7K4000 PK999999999999
da6:  31C Hitachi/HGST Ultrastar 7K4000 PK999999999999
da7:  21C INTEL SSDSC2BA100G3L  BTTV99999999999999
da8:  31C Hitachi/HGST Ultrastar 7K4000 PK999999999999
ada0:  29C Western Digital Green WD-WMAZA9999999
```
