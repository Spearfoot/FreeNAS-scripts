#!/bin/sh

rundate=$(date)

#################################################
# Backup the FreeNAS configuration file
#################################################

# Optional: specify your email address here if you want to receive notification
email=""

# Optional: specify the short name of your ESXi host if you are running FreeNAS
# as a VM and you want to back up the ESXi host's configuration
esxihost=""

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

echo "Backup FreeNAS configuration database file: ${fnconfigdest}" 

iscorral=$(< /etc/version grep "Corral" | awk {'print $1'})

if [ ! -z "${iscorral}" ]; then
  # FreeNAS Corral: make a CLI call:
  cli -e "system config download path=${fnconfigdest}"
else
  # FreeNAS 9.x: Copy the source to the destination:
  cp /data/freenas-v1.db "${fnconfigdest}"
fi

l_status=$?

#################################################
# Backup the VMware ESXi host configuration:
#################################################

if [ ! -z "${esxihost}" ]; then
  esxihostname=$(ssh root@"${esxihost}" hostname)
  esxiversion=$(ssh root@"${esxihost}" uname -a | sed -e "s|VMkernel ||;s|$esxihostname ||")
  esxiconfig_url=$(ssh root@"${esxihost}" vim-cmd hostsvc/firmware/backup_config | awk '{print $7}' | sed -e "s|*|$esxihostname|")
  esxiconfig_date=$(date +%Y%m%d%H%M%S)
  esxiconfig_file="${configdir}"/"${esxihost}"-configBundle-"${esxiconfig_date}".tgz
  
  echo "Downloading $esxiconfig_url to $esxiconfig_file"
  wget --no-check-certificate --output-document="${esxiconfig_file}" "${esxiconfig_url}"
fi

#################################################
# Send email notification if indicated:
#################################################

if [ ! -z "${email}" ]; then
  freenashostuc=$(hostname -s | tr '[:lower:]' '[:upper:]')
  freenashostname=$(hostname)
  freenasversion=$(cat /etc/version) 
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
    echo "FreeNAS:"
    echo "Server: ${freenashostname}"
    echo "Version: ${freenasversion}"
    echo "File: ${fnconfigdest}"
    if [ ! -z "${esxihost}" ]; then
      echo ""
      echo "ESXi:"
      echo "Server: ${esxihostname}"
      echo "Version: ${esxiversion}"
      echo "File: ${esxiconfig_file}"
    fi
    echo "</pre>"
  ) > ${logfile}
  sendmail ${email} < ${logfile}
  rm ${logfile}
fi


