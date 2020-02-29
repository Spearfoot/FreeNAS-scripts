#!/bin/sh

### Parameters ###

# Specify your email address here:
email=""

# Full path to 'smartctl' program:
smartctl=/usr/local/sbin/smartctl

freenashost=$(hostname -s | tr '[:lower:]' '[:upper:]')
boundary="===== MIME boundary; FreeNAS server ${freenashost} ====="
logfile="/tmp/smart_report.tmp"
subject="SMART Status Report for ${freenashost}"
tempWarn=40
tempCrit=45
sectorsCrit=10
testAgeWarn=1
warnSymbol="?"
critSymbol="!"

# We need a list of the SMART-enabled drives on the system. Choose one of these
# three methods to provide the list. Comment out the two unused sections of code.

# 1. A string constant; just key in the devices you want to report on here:
#drives="da1 da2 da3 da4 da5 da6 da7 da8 ada0"

# 2. A systcl-based technique suggested on the FreeNAS forum:
#drives=$(for drive in $(sysctl -n kern.disks); do \
#if [ "$("${"$smartctl"}" -i /dev/${drive} | grep "SMART support is: Enabled" | awk '{print $3}')" ]
#then printf ${drive}" "; fi done | awk '{for (i=NF; i!=0 ; i--) print $i }')

# 3. A "$smartctl"-based function:
get_smart_drives()
{
  gs_smartdrives=""
  gs_drives=$("$smartctl" --scan | awk '{print $1}')

  for gs_drive in $gs_drives; do
    gs_smart_flag=$("$smartctl" -i "$gs_drive" | egrep "SMART support is:[[:blank:]]+Enabled" | awk '{print $4}')
    if [ "$gs_smart_flag" = "Enabled" ]; then
      gs_smartdrives="$gs_smartdrives $gs_drive"
    fi
  done

  echo "$gs_smartdrives"
}

drives=$(get_smart_drives)

# end of method 3.

### Set email headers ###
printf "%s\n" "To: ${email}
Subject: ${subject}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$boundary\"

--${boundary}
Content-Type: text/html; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline
<html><head></head><body><pre style=\"font-size:14px\">" > ${logfile}

###### summary ######
(
 echo "########## SMART status report summary for all drives on server ${freenashost} ##########"
 echo ""
 echo "+------+------------------------+----+-----+-----+-----+-------+-------+--------+------+----------+------+-------+----+"
 echo "|Device|Serial                  |Temp|Power|Start|Spin |ReAlloc|Current|Offline |Seek  |Total     |High  |Command|Last|"
 echo "|      |Number                  |    |On   |Stop |Retry|Sectors|Pending|Uncorrec|Errors|Seeks     |Fly   |Timeout|Test|"
 echo "|      |                        |    |Hours|Count|Count|       |Sectors|Sectors |      |          |Writes|Count  |Age |"
 echo "+------+------------------------+----+-----+-----+-----+-------+-------+--------+------+----------+------+-------+----+"
) >> "$logfile"

for drive in $drives; do
  (
  devid=$(basename "$drive")
  lastTestHours=$("$smartctl" -l selftest "$drive" | grep "# 1" | awk '{print $9}')
  "$smartctl" -A -i -v 7,hex48 "$drive" | \
  awk -v device="$devid" -v tempWarn="$tempWarn" -v tempCrit="$tempCrit" -v sectorsCrit="$sectorsCrit" \
  -v testAgeWarn="$testAgeWarn" -v warnSymbol="$warnSymbol" -v critSymbol="$critSymbol" \
  -v lastTestHours="$lastTestHours" '
  /Serial Number:/{serial=$3}
  /190 Airflow_Temperature/{temp=$10}
  /194 Temperature/{temp=$10}
  /Power_On_Hours/{split($10,a,"+");sub(/h/,"",a[1]);onHours=a[1];}
  /Start_Stop_Count/{startStop=$10}
  /Spin_Retry_Count/{spinRetry=$10}
  /Reallocated_Sector/{reAlloc=$10}
  /Current_Pending_Sector/{pending=$10}
  /Offline_Uncorrectable/{offlineUnc=$10}
  /Seek_Error_Rate/{seekErrors=("0x" substr($10,3,4));totalSeeks=("0x" substr($10,7))}
  /High_Fly_Writes/{hiFlyWr=$10}
  /Command_Timeout/{cmdTimeout=$10}
  END {
      testAge=sprintf("%.0f", (onHours - lastTestHours) / 24);
      if (temp > tempCrit || reAlloc > sectorsCrit || pending > sectorsCrit || offlineUnc > sectorsCrit)
          device=device " " critSymbol;
      else if (temp > tempWarn || reAlloc > 0 || pending > 0 || offlineUnc > 0 || testAge > testAgeWarn)
          device=device " " warnSymbol;
      seekErrors=sprintf("%d", seekErrors);
      totalSeeks=sprintf("%d", totalSeeks);
      if (totalSeeks == "0") {
          seekErrors="N/A";
          totalSeeks="N/A";
      }
      if (temp > tempWarn || temp > tempCrit)
         temp=temp"*"
      else
         temp=temp" "

      if (reAlloc > 0 || reAlloc > sectorsCrit)
         reAlloc=reAlloc"*"
      
      if (pending > 0 || pending > sectorsCrit)
         pending=pending"*"

      if (offlineUnc > 0 || offlineUnc > sectorsCrit)
         offlineUnc=offlineUnc"*"

      if (testAge > testAgeWarn)
         testAge=testAge"*"
      
      if (hiFlyWr == "") hiFlyWr="N/A";
      if (cmdTimeout == "") cmdTimeout="N/A";
      printf "|%-6s|%-24s| %3s|%5s|%5s|%5s|%7s|%7s|%8s|%6s|%10s|%6s|%7s|%4s|\n",
      device, serial, temp, onHours, startStop, spinRetry, reAlloc, pending, offlineUnc,
      seekErrors, totalSeeks, hiFlyWr, cmdTimeout, testAge;
      }'
  ) >> "$logfile"
done

(
  echo "+------+------------------------+----+-----+-----+-----+-------+-------+--------+------+----------+------+-------+----+"
) >> "$logfile"

###### for each drive ######
for drive in $drives; do
  brand=$("$smartctl" -i "$drive" | grep "Model Family" | awk '{print $3, $4, $5, $6, $7}')
  if [ -z "$brand" ]; then
    brand=$("$smartctl" -i "$drive" | grep "Device Model" | awk '{print $3, $4, $5, $6, $7}')
  fi
  serial=$("$smartctl" -i "$drive" | grep "Serial Number" | awk '{print $3}')
  (
  echo ""
  echo "########## SMART status report for $drive drive (${brand}: ${serial}) ##########"
  "$smartctl" -n never -H -A -l error "$drive"
  "$smartctl" -n never -l selftest "$drive" | grep "# 1 \\|Num" | cut -c6-
  ) >> "$logfile"
done

sed -i '' -e '/smartctl 7.*/d' "$logfile"
sed -i '' -e '/smartctl 6.*/d' "$logfile"
sed -i '' -e '/smartctl 5.*/d' "$logfile"
sed -i '' -e '/smartctl 4.*/d' "$logfile"
sed -i '' -e '/Copyright/d' "$logfile"
sed -i '' -e '/=== START OF READ/d' "$logfile"
sed -i '' -e '/SMART Attributes Data/d' "$logfile"
sed -i '' -e '/Vendor Specific SMART/d' "$logfile"
sed -i '' -e '/SMART Error Log Version/d' "$logfile"

printf "%s\n" "</pre></body></html>
--${boundary}--" >> ${logfile}

### Send report ###
if [ -z "${email}" ]; then
  echo "No email address specified, information available in ${logfile}"
else
  sendmail -t -oi < "$logfile"
  rm "$logfile"
fi
