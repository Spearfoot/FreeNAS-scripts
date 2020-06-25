#!/bin/sh

#################################################
# Backup FreeNAS configuration files
# 
# Copies the FreeNAS sqlite3 configuration and password secret
# seed files to the location you specify in the 'configdir'
# variable below.
# 
# OPTIONAL: 
# 
# By specifying your email address in the 'email' variable, you may choose to
# have the configuration file emailed to you in an encrypted tarball.
# 
#################################################

rundate=$(date)

# Optional: specify your email address here if you want to the script to email
# you the configuration file in an encrypted tarball. 
# 
# Leave the email address blank to simply copy the configuration file to the
# destination you specify with the 'configdir' setting below.
email=""

# Specify the dataset on your system where you want the configuration files copied.
# Don't include the trailing slash.

# Example: configdir=/mnt/tank/sysadmin/config
configdir=""

# OpenSSL encryption passphrase file. Enter the passphrase on the the first line in
# the file. This file should have 0600 permissions.
enc_passphrasefile=/root/config_passphrase

# FreeNAS hostname:
freenashost=$(hostname -s)

# MIME boundary
mime_boundary="==>>> MIME boundary; FreeNAS server [${freenashost}] <<<=="

#################################################
# Append file attachment to current email message
#################################################
 
append_file() 
{
  l_mimetype=""

  if [ -f "$1" ]; then
    l_mimetype=$(file --mime-type "$1" | sed 's/.*: //')

    printf '%s\n' "--${mime_boundary}
Content-Type: $l_mimetype
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename=\"$(basename "$1")\"
"
    base64 "$1"
    echo
  fi
}

#################################################
# Backup the FreeNAS configuration file
#################################################

fnconfigdest_version=$(< /etc/version sed -e 's/)//;s/(//;s/ /-/' | tr -d '\n') 
fnconfigdest_date=$(date +%Y%m%d%H%M%S)
fnconfigdest_base="$freenashost"-"$fnconfigdest_version"-"$fnconfigdest_date".db
fnconfigdest="$configdir"/"$fnconfigdest_base"
fnconfigtarball=./"$freenashost"-"$fnconfigdest_version"-"$fnconfigdest_date".tar.gz
fnconfigtarballenc=./"$freenashost"-"$fnconfigdest_version"-"$fnconfigdest_date".tar.gz.enc

echo "Backup configuration database file: $fnconfigdest" 

# Copy the source database and password encryption secret seed file to the destination:

/usr/local/bin/sqlite3 /data/freenas-v1.db ".backup main '${fnconfigdest}'"
l_status=$?
cp -f /data/pwenc_secret "$configdir"

if [ -z "$email" ]; then
# No email message requested, show status and exit:
  echo "Configuration file copied with status ${l_status}"
  exit $l_status
fi

#########################################################
# Send email message with encrypted config files attached
#########################################################

fnconfigtarball=./"$freenashost"-"$fnconfigdest_version"-"$fnconfigdest_date".tar.gz
fnconfigtarballenc=./"$freenashost"-"$fnconfigdest_version"-"$fnconfigdest_date".tar.gz.enc

# Validate the configuration file and create tarball:

if [ $l_status -eq 0 ]; then
  dbstatus=$(sqlite3 "$fnconfigdest" "pragma integrity_check;")
  printf 'sqlite3 status: [%s]\n' "$dbstatus"
  if [ "$dbstatus" = "ok" ]; then
    tar -czvf "$fnconfigtarball" -C "$configdir" "$fnconfigdest_base" pwenc_secret
    l_status=$?
    printf 'tar status: [%s]\n' "$l_status"
  else
    l_status=1
  fi
  if [ $l_status -eq 0 ]; then
    openssl enc -e -aes-256-cbc -md sha512 -salt -S "$(openssl rand -hex 4)" -pass file:"$enc_passphrasefile" -in "$fnconfigtarball" -out "$fnconfigtarballenc"
    l_status=$?
    printf 'openssl status: [%s]\n' "$l_status"
  fi
fi

freenashostuc=$(hostname -s | tr '[:lower:]' '[:upper:]')
freenashostname=$(hostname)
freenasversion=$(cat /etc/version) 
if [ $l_status -eq 0 ]; then
  subject="FreeNAS configuration saved on server ${freenashostuc}"
  savestatus="FreeNAS configuration file saved successfully on ${rundate}"
else
  subject="FreeNAS configuration backup failed on server ${freenashostuc}"
  savestatus="FreeNAS configuration backup failed with status=${l_status} on ${rundate}"
fi
logfile="/tmp/save_config_enc.tmp"
{ 
printf '%s\n' "From: root
To: ${email}
Subject: ${subject}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$mime_boundary\"

--${mime_boundary}
Content-Type: text/plain; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline

${savestatus}

Server: ${freenashostname}
Version: ${freenasversion}
File: ${fnconfigdest}
"

if [ $l_status -eq 0 ]; then
  append_file "$fnconfigtarballenc"
fi

# print last boundary with closing --
printf '%s\n' "--${mime_boundary}--"
} > "$logfile"

sendmail -t -oi < "$logfile"
rm "$logfile"
rm "$fnconfigtarball"
rm "$fnconfigtarballenc"



