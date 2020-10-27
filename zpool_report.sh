#!/bin/sh

### Parameters ###

# Specify your email address here:
email=""

# zpool output changed from FreeNAS version 11.0 to 11.1, breaking
# our parsing of the scrubErrors and scrubDate variables. Added a
# conditional to test for the FreeNAS version and parse accordingly.
# This changed again with the release of TrueNAS. Ironically, back to
# the way parsing worked with older versions of FreeNAS.
# 
# We obtain the FreeBSD version using uname, as suggested by user
# Chris Moore on the FreeBSD forum.
# 
# 'uname -K' gives 7-digit OS release and version, e.g.:
#
#   FreeBSD 11.0  1100512
#   FreeBSD 11.1  1101505
#   FreeBSD 12.2  1202000
 
fbsd_relver=$(uname -K)

freenashost=$(hostname -s | tr '[:lower:]' '[:upper:]')
boundary="===== MIME boundary; FreeNAS server ${freenashost} ====="
logfile="/tmp/zpool_report.tmp"
subject="ZPool Status Report for ${freenashost}"
pools=$(zpool list -H -o name)
usedWarn=75
usedCrit=90
scrubAgeWarn=30
warnSymbol="?"
critSymbol="!"

### Set email headers ###
printf "%s\n" "To: ${email}
Subject: ${subject}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$boundary\"

--${boundary}
Content-Type: text/html; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline
<html><head></head><body><pre style=\"font-size:14px; white-space:pre\">" >> ${logfile}

###### summary ######
(
  echo "########## ZPool status report summary for all pools on server ${freenashost} ##########"
  echo ""
  echo "+--------------+--------+------+------+------+----+----+--------+------+-----+"
  echo "|Pool Name     |Status  |Read  |Write |Cksum |Used|Frag|Scrub   |Scrub |Last |"
  echo "|              |        |Errors|Errors|Errors|    |    |Repaired|Errors|Scrub|"
  echo "|              |        |      |      |      |    |    |Bytes   |      |Age  |"
  echo "+--------------+--------+------+------+------+----+----+--------+------+-----+"
) >> ${logfile}

for pool in $pools; do
  if [ "$fbsd_relver" -ge 1101000 ]; then
    frag="$(zpool list -H -o frag "$pool")"   
  else
    if [ "${pool}" = "freenas-boot" ] || [ "${pool}" = "boot-pool" ]; then
      frag=""
    else
      frag="$(zpool list -H -o frag "$pool")"
    fi
  fi

  status="$(zpool list -H -o health "$pool")"
  errors="$(zpool status "$pool" | grep -E "(ONLINE|DEGRADED|FAULTED|UNAVAIL|REMOVED)[ \t]+[0-9]+")"
  readErrors=0
  for err in $(echo "$errors" | awk '{print $3}'); do
    if echo "$err" | grep -E -q "[^0-9]+"; then
      readErrors=1000
      break
    fi
    readErrors=$((readErrors + err))
  done
  writeErrors=0
  for err in $(echo "$errors" | awk '{print $4}'); do
    if echo "$err" | grep -E -q "[^0-9]+"; then
      writeErrors=1000
      break
    fi
    writeErrors=$((writeErrors + err))
  done
  cksumErrors=0
  for err in $(echo "$errors" | awk '{print $5}'); do
    if echo "$err" | grep -E -q "[^0-9]+"; then
      cksumErrors=1000
      break
    fi
    cksumErrors=$((cksumErrors + err))
  done
  if [ "$readErrors" -gt 999 ]; then readErrors=">1K"; fi
  if [ "$writeErrors" -gt 999 ]; then writeErrors=">1K"; fi
  if [ "$cksumErrors" -gt 999 ]; then cksumErrors=">1K"; fi
  used="$(zpool list -H -p -o capacity "$pool")"
  scrubRepBytes="N/A"
  scrubErrors="N/A"
  scrubAge="N/A"
  if [ "$(zpool status "$pool" | grep "scan" | awk '{print $2}')" = "scrub" ]; then
    scrubRepBytes="$(zpool status "$pool" | grep "scan" | awk '{print $4}')"
    if [ "$fbsd_relver" -gt 1101000 ] && [ "$fbsd_relver" -lt 1200000 ]; then
      scrubErrors="$(zpool status "$pool" | grep "scan" | awk '{print $10}')"
      scrubDate="$(zpool status "$pool" | grep "scan" | awk '{print $17"-"$14"-"$15"_"$16}')"
    else
      scrubErrors="$(zpool status "$pool" | grep "scan" | awk '{print $8}')"
      scrubDate="$(zpool status "$pool" | grep "scan" | awk '{print $15"-"$12"-"$13"_"$14}')"
    fi
    scrubTS="$(date -j -f "%Y-%b-%e_%H:%M:%S" "$scrubDate" "+%s")"
    currentTS="$(date "+%s")"
    scrubAge=$((((currentTS - scrubTS) + 43200) / 86400))
  fi
  if [ "$status" = "FAULTED" ] || [ "$used" -gt "$usedCrit" ]; then
    symbol="$critSymbol"  
  elif [ "$scrubErrors" != "N/A" ] && [ "$scrubErrors" != "0" ]; then
    symbol="$critSymbol"
  elif [ "$status" != "ONLINE" ] \
  || [ "$readErrors" != "0" ] \
  || [ "$writeErrors" != "0" ] \
  || [ "$cksumErrors" != "0" ] \
  || [ "$used" -gt "$usedWarn" ] \
  || [ "$(echo "$scrubAge" | awk '{print int($1)}')" -gt "$scrubAgeWarn" ]; then
    symbol="$warnSymbol"  
  elif [ "$scrubRepBytes" != "0" ] &&  [ "$scrubRepBytes" != "0B" ] && [ "$scrubRepBytes" != "N/A" ]; then
    symbol="$warnSymbol"
  else
    symbol=" "
  fi
  (
  printf "|%-12s %1s|%-8s|%6s|%6s|%6s|%3s%%|%4s|%8s|%6s|%5s|\n" \
  "$pool" "$symbol" "$status" "$readErrors" "$writeErrors" "$cksumErrors" \
  "$used" "$frag" "$scrubRepBytes" "$scrubErrors" "$scrubAge"
  ) >> ${logfile}
  done

(
  echo "+--------------+--------+------+------+------+----+----+--------+------+-----+"
) >> ${logfile}

###### for each pool ######
for pool in $pools; do
  (
  echo ""
  echo "########## ZPool status report for ${pool} ##########"
  echo ""
  zpool status -v "$pool"
  ) >> ${logfile}
done

printf "%s\n" "</pre></body></html>
--${boundary}--" >> ${logfile}

### Send report ###
if [ -z "${email}" ]; then
  echo "No email address specified, information available in ${logfile}"
else
  sendmail -t -oi < ${logfile}
  rm ${logfile}
fi
