# FreeNAS Scripts
Bash scripts for use on FreeNAS servers

These are my versions of useful scripts available at the ["Scripts to report SMART, ZPool and UPS status, HDD/CPU T°, HDD identification and backup the config"](https://forums.freenas.org/index.php?threads/scripts-to-report-smart-zpool-and-ups-status-hdd-cpu-t%C2%B0-hdd-identification-and-backup-the-config.27365/) thread on the FreeNAS forum. The original author is FreeNAS forum member BiduleOhm, with others contributing suggestions and code changes.

I have modified the syntax, using the excellent Bash lint system at https://www.shellcheck.net as a guide, and have made minor changes in formatting and spacing of the generated reports.

# smart_report.sh

Generates and emails you a status report with detailed SMART information about your system's drives.

By default, my version of this script uses a function I wrote which uses smartctl's scan list to obtain the SMART-enabled drives on the system, but you have the option of using either a hard-coded list or a sysctl-based method instead, if you so choose. This version allows for serial numbers up to 18 characters in length, where the original only supported 15. It also selects the "Device Model" as the drive 'brand' if the "Model Family" SMART attribute is unavailable.

You will need to edit the script and enter your email address before using it.

# zpool_report.sh

Generates and emails you a status report about your system's pools.

You will need to edit the script and enter your email address before using it.

# save_config.sh

Copies the FreeNAS system configuration file to a dataset you specify. The backup filenames are formed from the hostname, complete FreeNAS version, and date, in this format: _hostname-freenas_version-date.db_. Here is an example from a recent backup on my server named _boomer_:

  __boomer-FreeNAS-9.10.2-U2-e1497f2-20170315224905.db__

Edit this script and specify the target dataset where you want the backup files copied.
