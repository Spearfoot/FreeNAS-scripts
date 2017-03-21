#!/bin/sh

#################################################
# Backup the FreeNAS configuration file
#################################################

# Specify the dataset on your system where you want the configuration files copied.
# Don't include the trailing slash.

# Example: configdir=/mnt/tank/sysadmin/config

configdir=""

# Remove this code once you've defined configdir above... :-)

if [ -z ${configdir} ]; then
  echo "Edit script and specify the target directory ('configdir') before using $0"
  exit 2
fi

freenashost=$(hostname -s)

fnconfigdest_version=$(< /etc/version sed -e 's/)//;s/(//;s/ /-/' | tr -d '\n') 
fnconfigdest_date=$(date +%Y%m%d%H%M%S)
fnconfigdest="${configdir}"/"${freenashost}"-"${fnconfigdest_version}"-"${fnconfigdest_date}".db

echo "Backup configuration database file: ${fnconfigdest}" 

# Copy the source to the destination:

cp /data/freenas-v1.db "${fnconfigdest}"
