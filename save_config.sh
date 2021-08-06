#!/bin/sh

#####
# Backup the TrueNAS/FreeNAS configuration database and password secret encryption files
#####

# REQUIRED: Specify the dataset on your system where you want the configuration files copied.
# Don't include the trailing slash.

# Example: configdir="/mnt/tank/sysadmin/config"

configdir=""

# Remove this code once you've defined configdir above... :-)

if [ -z "${configdir}" ]; then
  echo "Edit script and specify the target directory ('configdir') before using $0"
  exit 2
fi

# Optional: Set non-zero 'do_tar' flag to have both files stored in a tarball as typically
# needed when restoring a configuration.
do_tar=1

# Optional: specify your email address here if you want to receive a notification message.
notifyemail=""

# Optional: specify the short name of your ESXi host if you are running FreeNAS
# as a VM and you want to back up the ESXi host's configuration
esxihost=""

# Get the date and version of TrueNAS/FreeNAS:

rundate=$(date)

osvers=$(grep -i truenas /etc/version)
if [ -z "${osvers}" ]; then
  osvers=$(grep -i freenas /etc/version)
  if [ -z "${osvers}" ]; then
    osvers="UNKNOWN"
  else
    osvers="FreeNAS"
  fi
else
  osvers="TrueNAS"
fi

# Form a unique, timestamped filename for the backup configuration database and tarball

P1=$(hostname -s)
P2=$(< /etc/version sed -e 's/)//;s/(//;s/ /-/' | tr -d '\n') 
P3=$(date +%Y%m%d%H%M%S)
fnconfigdest_base="$P1"-"$P2"-"$P3"
fnconfigdestdb="${configdir}"/"${fnconfigdest_base}".db
fnconfigtarball="${configdir}"/"${fnconfigdest_base}".tar

# Copy the source database and password encryption secret key to the destination:

echo "Backup ${osvers} configuration database file: ${fnconfigdestdb}" 

cp -f /data/pwenc_secret "$configdir"
/usr/local/bin/sqlite3 /data/freenas-v1.db ".backup main '${fnconfigdestdb}'"
l_status=$?

# Validate the configuration file and create tarball:

if [ $l_status -eq 0 ]; then
  dbstatus=$(sqlite3 "$fnconfigdestdb" "pragma integrity_check;")
  printf 'sqlite3 status: [%s]\n' "${dbstatus}"
  if [ "${dbstatus}" = "ok" ]; then
    l_status=0
    if [ $do_tar -ne 0 ]; then
	  # Save the config DB w/ its original name in the tarball -- makes restoring them easier:
	  cp -f "${fnconfigdestdb}" "${configdir}"/freenas-v1.db
      tar -cvf "${fnconfigtarball}" -C "${configdir}" freenas-v1.db pwenc_secret
      l_status=$?
      printf 'tar status: [%s]\n' "${l_status}"
    fi
  else
    l_status=1
  fi
fi

if [ $l_status -eq 0 ]; then
  echo "Success backing up configuration files to directory ${configdir}"
else
  echo "Error backing up configuration files to directory ${configdir}"
fi
l_status=$?

# Backup the VMware ESXi host configuration:

if [ -n "${esxihost}" ]; then
  esxihostname=$(ssh root@"${esxihost}" hostname)
  esxiversion=$(ssh root@"${esxihost}" uname -a | sed -e "s|VMkernel ||;s|$esxihostname ||")
  esxiconfig_url=$(ssh root@"${esxihost}" vim-cmd hostsvc/firmware/backup_config | awk '{print $7}' | sed -e "s|*|$esxihostname|")
  esxiconfig_date=$(date +%Y%m%d%H%M%S)
  esxiconfig_file="${configdir}"/"${esxihost}"-configBundle-"${esxiconfig_date}".tgz
  
  echo "Downloading $esxiconfig_url to $esxiconfig_file"
  wget --no-check-certificate --output-document="${esxiconfig_file}" "${esxiconfig_url}"
fi

# Send email notification if indicated:

if [ -n "${notifyemail}" ]; then
  freenashostuc=$(hostname -s | tr '[:lower:]' '[:upper:]')
  freenashostname=$(hostname)
  freenasversion=$(< /etc/version sed -e 's/)//;s/(//;s/ /-/' | tr -d '\n')
  boundary="===== MIME boundary; ${osvers} server ${freenashostname} =====" 
  logfile="/tmp/save_config.tmp"
  if [ $l_status -eq 0 ]; then
    subject="${osvers} configuration saved on server ${freenashostuc}"
  else
    subject="${osvers} configuration backup failed on server ${freenashostuc}"
  fi
  
  printf "%s\n" "To: ${notifyemail}
Subject: ${subject}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$boundary\"

--${boundary}
Content-Type: text/html; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline
<html><head></head><body><pre style=\"font-size:14px; white-space:pre\">" > ${logfile} 
  
(
    if [ $l_status -eq 0 ]; then
      echo "Configuration file saved successfully on ${rundate}"
    else
      echo "Configuration backup failed with status=${l_status} on ${rundate}"
    fi
    echo ""
    echo "--- ${osvers} ---"
    echo "Server: ${freenashostname}"
    echo "Version: ${freenasversion}"
    echo "Files:"
	echo "  ${fnconfigdestdb}"
	echo "  ${configdir}/pwenc_secret"
    if [ "$do_tar" -ne 0 ]; then	
	   echo "  ${fnconfigtarball}"
	fi 
    if [ -n "${esxihost}" ]; then
      echo ""
      echo "--- ESXi ---"
      echo "Server: ${esxihostname}"
      echo "Version: ${esxiversion}"
      echo "File: ${esxiconfig_file}"
    fi
) >> ${logfile}
  
  printf "%s\n" "</pre></body></html>
--${boundary}--" >> ${logfile}  

  sendmail -t -oi < ${logfile}
  rm ${logfile}
fi


