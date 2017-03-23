#!/bin/sh

#################################################
# Backup the FreeNAS configuration file
#################################################

# Optional: specify your email address here if you want to receive notification
email=""

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
l_status=$?

# Send email notification if indicated:

if [ ! -z "${email}" ]; then
  freenashostuc=$(hostname -s | tr '[:lower:]' '[:upper:]')
  freenashostname=$(hostname)
  freenasversion=$(cat /etc/version) 
  rundate=$(date)
  logfile="/tmp/save_config.tmp"
  if [ $l_status -eq 0 ]; then
    subject="FreeNAS configuration saved on server ${freenashostuc}"
  else
    subject="FreeNAS configuration backup failed on server ${freenashostuc}"
  fi
  (
    echo "To: ${email}"
    echo "Subject: ${subject}"
    echo "Content-Type: text/html"
    echo "MIME-Version: 1.0"
    printf "\r\n"
    echo "<pre style=\"font-size:14px\">"
    if [ $l_status -eq 0 ]; then
      echo "Configuration file saved successfully on ${rundate}"
    else
      echo "Configuration backup failed with status=${l_status} on ${rundate}"
    fi
    echo ""
    echo "Server: ${freenashostname}"
    echo "Version: ${freenasversion}"
    echo "File: ${fnconfigdest}"
    echo "</pre>"
  ) > ${logfile}
  sendmail ${email} < ${logfile}
  rm ${logfile}
fi


