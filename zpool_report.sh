#!/bin/sh

### Parameters ###

# Specify your email address here:
email=""

freenashost=$(hostname -s | tr '[:lower:]' '[:upper:]')
logfile="/tmp/zpool_report.tmp"
subject="ZPool Status Report for ${freenashost}"
pools=$(zpool list -H -o name)
usedWarn=75
usedCrit=90
scrubAgeWarn=30
warnSymbol="?"
critSymbol="!"

### Set email headers ###
(
  echo "To: ${email}"
  echo "Subject: ${subject}"
  echo "Content-Type: text/html"
  echo "MIME-Version: 1.0"
  printf "\r\n"
) > ${logfile}

### Set email body ###
echo "<pre style=\"font-size:14px\">" >> ${logfile}

###### summary ######
(
  echo "########## ZPool status report summary for all pools on server ${freenashost} ##########"
  echo ""
  echo "+--------------+--------+------+------+------+----+--------+------+-----+"
  echo "|Pool Name     |Status  |Read  |Write |Cksum |Used|Scrub   |Scrub |Last |"
  echo "|              |        |Errors|Errors|Errors|    |Repaired|Errors|Scrub|"
  echo "|              |        |      |      |      |    |Bytes   |      |Age  |"
  echo "+--------------+--------+------+------+------+----+--------+------+-----+"
) >> ${logfile}

for pool in $pools; do
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
    scrubErrors="$(zpool status "$pool" | grep "scan" | awk '{print $8}')"
    scrubDate="$(zpool status "$pool" | grep "scan" | awk '{print $15"-"$12"-"$13"_"$14}')"
    scrubTS="$(date -j -f "%Y-%b-%e_%H:%M:%S" "$scrubDate" "+%s")"
    currentTS="$(date "+%s")"
    scrubAge=$((((currentTS - scrubTS) + 43200) / 86400))
  fi
  if [ "$status" = "FAULTED" ] \
  || [ "$used" -gt "$usedCrit" ] \
  || ( [ "$scrubErrors" != "N/A" ] && [ "$scrubErrors" != "0" ] )
  then
    symbol="$critSymbol"
  elif [ "$status" != "ONLINE" ] \
  || [ "$readErrors" != "0" ] \
  || [ "$writeErrors" != "0" ] \
  || [ "$cksumErrors" != "0" ] \
  || [ "$used" -gt "$usedWarn" ] \
  || [ "$scrubRepBytes" != "0" ] \
  || [ "$(echo "$scrubAge" | awk '{print int($1)}')" -gt "$scrubAgeWarn" ]
  then
    symbol="$warnSymbol"
  else
    symbol=" "
  fi
  (
  printf "|%-12s %1s|%-8s|%6s|%6s|%6s|%3s%%|%8s|%6s|%5s|\n" \
  "$pool" "$symbol" "$status" "$readErrors" "$writeErrors" "$cksumErrors" \
  "$used" "$scrubRepBytes" "$scrubErrors" "$scrubAge"
  ) >> ${logfile}
  done

(
  echo "+--------------+--------+------+------+------+----+--------+------+-----+"
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

echo "</pre>" >> ${logfile}

### Send report ###
if [ -z "${email}" ]; then
  echo "No email address specified, information available in ${logfile}"
else
#  sendmail -t < ${logfile}
  sendmail ${email} < ${logfile}
  rm ${logfile}
fi
