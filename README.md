# FreeNAS Scripts
Bash scripts for use on FreeNAS servers

These are my versions of useful scripts available at the ["Scripts to report SMART, ZPool and UPS status, HDD/CPU T°, HDD identification and backup the config"](https://forums.freenas.org/index.php?threads/scripts-to-report-smart-zpool-and-ups-status-hdd-cpu-t%C2%B0-hdd-identification-and-backup-the-config.27365/) thread on the FreeNAS forum. The original author is FreeNAS forum member BiduleOhm, with others contributing suggestions and code changes.

I have modified the syntax, using the excellent Bash lint system at https://www.shellcheck.net as a guide, and have made minor changes in formatting and spacing of the generated reports.

# smart_report.sh

By default, my version of this script uses a function I wrote which uses smartctl's scan list to obtain the SMART-enabled drives on the system, but you have the option of using either a hard-coded list or a sysctl-based method instead, if you so choose. This version allows for serial numbers up to 18 characters in length, where the original only supported 15. It also selects the "Device Model" as the drive 'brand' if the "Model Family" SMART attribute is unavailable.

You will need to edit the script and enter your email address before using it.

# zpool_report.sh

You will need to edit the script and enter your email address before using it.
