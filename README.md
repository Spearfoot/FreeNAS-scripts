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

Saves your FreeNAS system configuration file to a dataset you specify. 

Supports both the now-defunct Corral and all SQLite-based versions of FreeNAS: 11.x, 9.x, etc.

The backup filenames are formed from the hostname, complete FreeNAS version, and date, in this format: _hostname-freenas_version-date.db_. Here is an example from a recent backup on my server named _boomer_:

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
# save_config_enc.sh

Saves your FreeNAS system configuration file to a dataset you specify, optionally sending you an email message containing the configuration file in an encrypted tarball.

Supports the versions of FreeNAS which use an SQLite-based configuration file: these include FreeNAS 11.x, 9.x, and probably earlier versions as well... but not Corral. 

The backup filenames are formed from the hostname, complete FreeNAS version, and date, in this format: _hostname-freenas_version-date.db_. Here is an example from a recent backup on my server named _bandit_:

```
bandit-FreeNAS-11.0-RELEASE-a2dc21583-20170710234500.db
```

Edit this script and specify the target dataset where you want the backup files copied.

Optional feature: you may configure the script to send an email message whenever it script executes. The script will create an encrypted tarball containing the configuration file, which it will include with the email message as a MIME-encoded attachment. To enable this feature you must specify your email address and create a passphrase file.

The attachment filename is formed from the hostname, complete FreeNAS version, and date, in this format: _hostname-freenas_version-date.tar.gz.enc_. Here is an example from a recent backup on my server named _bandit_:

```
bandit-FreeNAS-11.0-RELEASE-a2dc21583-20170710234500.tar.gz.enc
```
To create the attachment, the script first validates the configuration file by testing it with the `sqlite3` program's `pragma integrity_check;` option. If successfull, it next uses `tar` to store the configuration file in a gzipped tarball. Finally, it encrypts the tarball file with `openssl`, using a default cipher type of `-aes256` and a passphrase you specify in a passphrase file. You may use a different cipher by modifying the `enc_cipher` variable. The passphrase file is simply a text file, with the passphrase stored in the first line of the file. Specify this file's location in the `enc_passphrasefile` variable.

To decrypt the email attachment, first save it to your local system. Then use this command to decrypt it:

`openssl enc -d -aes256 -pass file:[passphrase_file] -in [encrypted_file] -out [unencrypted_file]`

Where:
* `passphrase_file` is a file containing the same passphrase you configured on your FreeNAS server
* `encrypted_file` is your locally-saved copy of the email attachment
* `unencrypted_file` is the unencrypted contents of the email attachment
***
# set_hdd_erc.sh

Sets the Error Recovery Control (aka SCTERC or TLER) read and write values on your system's hard drives. What is this? There is a good discussion in the ["Checking for TLER, ERC, etc. support on a drive"](https://forums.freenas.org/index.php?threads/checking-for-tler-erc-etc-support-on-a-drive.27126/) thread on the FreeNAS forum, and you can find more gory details in [this FAQ](https://www.smartmontools.org/wiki/FAQ#WhatiserrorrecoverycontrolERCandwhyitisimportanttoenableitfortheSATAdisksinRAID) at the [smartmontools.org](https://www.smartmontools.org) website. This key quote from the FAQ sums up why you want to set this up on your FreeNAS servers:

>"It is best for ERC to be "enabled" when in a RAID array to prevent the recovery time from a disk read or write error from exceeding the RAID implementation's timeout threshold. If a drive times out, the hard disk will need to be manually re-added to the array, requiring a re-build and re-synchronization of the hard disk. Limiting the drives recovery timeout helps for improved error handling in the hardware or software RAID environments."

By default, the script sets both the read and write timeout value to 7 seconds. You can change either or both of these values to better suit your environment.

Some hard drives retain these values when powered down, but some do not - including the HGST 7K4000 drives I use in one of my systems. For this reason, I configure my FreeNAS servers to run `set_hdd_src.sh` as a post-init startup script.
***
# get_hdd_temp.sh

Displays the current temperature of your system's CPU and drives. 

By default, the script uses `sysctl` to determine the number of CPU cores and report their temperatures. This reports a temperature for each core on systems equipped with modern multi-core CPUs. The optional IPMI support, if enabled, reports a single temperature for each socketed CPU. The latter result is probably more useful for monitoring CPU status.

To enable IPMI support, edit the script and:
* Set the `use_ipmi` variable to `1`
* Specify the IPMI host's IP address or DNS-resolvable hostname in the `ipmihost` variable.
* Specify the IPMI username in the `ipmiuser` variable.
* Specify the IPMI password file location in the `ipmipwfile` variable. This is a simple text file containing the IPMI user's password on a single line. You should protect this file by setting its permissions to 0600.

Drive output includes: the device ID, temperature (in Centigrade), capacity, serial number, and drive family/model. Here is sample output from one of my systems equipped with dual CPUs, using the IPMI feature and with serial numbers obfuscated:

```
=== CPU (2) ===
CPU  1: [35C]
CPU  2: [38C]

=== DRIVES ===
   da1:   19C [8.58GB] SN9999999999999999   INTEL SSDSC2BA100G3L
   da2:   39C [4.00TB] SN9999999999999999   HGST Deskstar NAS (HGST HDN724040ALE640)
   da3:   36C [4.00TB] SN9999999999999999   HGST Deskstar NAS (HGST HDN724040ALE640)
   da4:   27C [240GB]  SN9999999999999999   Intel 730 and DC S35x0/3610/3700 (INTEL SSDSC2BB240G4)
   da5:   27C [2.00TB] SN9999999999999999   Western Digital Green (WDC WD20EARX-00PASB0)
   da6:   28C [2.00TB] SN9999999999999999   Western Digital Red (WDC WD20EFRX-68EUZN0)
   da7:   19C [8.58GB] SN9999999999999999   INTEL SSDSC2BA100G3L
   da8:   31C [6.00TB] SN9999999999999999   Western Digital Black (WDC WD6001FZWX-00A2VA0)
   da9:   29C [2.00TB] SN9999999999999999   Western Digital Green (WDC WD20EARX-00PASB0)
  da10:   29C [2.00TB] SN9999999999999999   Western Digital Red (WDC WD20EFRX-68EUZN0)
  da11:   34C [4.00TB] SN9999999999999999   HGST HDN726040ALE614
  da12:   37C [4.00TB] SN9999999999999999   HGST HDN726040ALE614
  da13:   37C [4.00TB] SN9999999999999999   Western Digital Re (WDC WD4000FYYZ-01UL1B1)
  da14:   38C [4.00TB] SN9999999999999999   Western Digital Re (WDC WD4000FYYZ-01UL1B1)
```
(Thanks to P. Robar for his helpful suggestions with respect to `sysctl` usage and the `get_smart_drives()` function.)
