#!/bin/sh

### Parameters ###

# Specify your email address here:
email=""

freenashost=$(hostname -s | tr '[:lower:]' '[:upper:]')
logfile="/tmp/smart_report.tmp"
subject="SMART Status Report for ${freenashost}"
tempWarn=40
tempCrit=45
sectorsCrit=10
warnSymbol="?"
critSymbol="!"

# We need a list of the SMART-enabled drives on the system. Choose one of these
# three methods to provide the list. Comment out the two unused sections of code.

# 1. A string constant; just key in the devices you want to report on here:
#drives="da1 da2 da3 da4 da5 da6 da7 da8 ada0"

# 2. A systcl-based technique suggested on the FreeNAS forum:
#drives=$(for drive in $(sysctl -n kern.disks); do \
#if [ "$(/usr/local/sbin/smartctl -i /dev/${drive} | grep "SMART support is: Enabled" | awk '{print $3}')" ]
#then printf ${drive}" "; fi done | awk '{for (i=NF; i!=0 ; i--) print $i }')

# 3. A smartctl-based function:
get_smart_drives()
{
  gs_drives=$(/usr/local/sbin/smartctl --scan | grep "dev" | awk '{print $1}' | sed -e 's/\/dev\///' | tr '\n' ' ')

  gs_smartdrives=""

  for gs_drive in $gs_drives; do
    gs_smart_flag=$(/usr/local/sbin/smartctl -i /dev/"$gs_drive" | grep "SMART support is: Enabled" | awk '{print $4}')
    if [ "$gs_smart_flag" = "Enabled" ]; then
      gs_smartdrives=$gs_smartdrives" "${gs_drive}
    fi
  done

  eval "$1=\$gs_smartdrives"
}

drives=""
get_smart_drives drives

# end of method 3.

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
 echo "########## SMART status report summary for all drives on server ${freenashost} ##########"
 echo ""
 echo "+------+------------------+----+-----+-----+-----+-------+-------+--------+------+----------+------+-------+"
 echo "|Device|Serial            |Temp|Power|Start|Spin |ReAlloc|Current|Offline |Seek  |Total     |High  |Command|"
 echo "|      |Number            |    |On   |Stop |Retry|Sectors|Pending|Uncorrec|Errors|Seeks     |Fly   |Timeout|"
 echo "|      |                  |    |Hours|Count|Count|       |Sectors|Sectors |      |          |Writes|Count  |"
 echo "+------+------------------+----+-----+-----+-----+-------+-------+--------+------+----------+------+-------+"
) >> ${logfile}

for drive in $drives; do
  (
  /usr/local/sbin/smartctl -A -i -v 7,hex48 /dev/"${drive}" | \
  awk -v device="${drive}" -v tempWarn=${tempWarn} -v tempCrit=${tempCrit} -v sectorsCrit=${sectorsCrit} \
  -v warnSymbol="${warnSymbol}" -v critSymbol=${critSymbol} '
  /Serial Number:/{serial=$3}
  /Temperature_Celsius/{temp=$10}
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
      if (temp > tempCrit || reAlloc > sectorsCrit || pending > sectorsCrit || offlineUnc > sectorsCrit)
          device=device " " critSymbol;
      else if (temp > tempWarn || reAlloc > 0 || pending > 0 || offlineUnc > 0)
          device=device " " warnSymbol;
      seekErrors=sprintf("%d", seekErrors);
      totalSeeks=sprintf("%d", totalSeeks);
      if (totalSeeks == "0") {
          seekErrors="N/A";
          totalSeeks="N/A";
      }
      if (hiFlyWr == "") hiFlyWr="N/A";
      if (cmdTimeout == "") cmdTimeout="N/A";
      printf "|%-6s|%-18s| %s |%5s|%5s|%5s|%7s|%7s|%8s|%6s|%10s|%6s|%7s|\n",
      device, serial, temp, onHours, startStop, spinRetry, reAlloc, pending, offlineUnc,
      seekErrors, totalSeeks, hiFlyWr, cmdTimeout;
      }'
  ) >> ${logfile}
done

(
  echo "+------+------------------+----+-----+-----+-----+-------+-------+--------+------+----------+------+-------+"
) >> ${logfile}

###### for each drive ######
for drive in $drives; do
  brand=$(/usr/local/sbin/smartctl -i /dev/"${drive}" | grep "Model Family" | awk '{print $3, $4, $5}')
  if [ -z "$brand" ]; then
    brand=$(/usr/local/sbin/smartctl -i /dev/"${drive}" | grep "Device Model" | awk '{print $3, $4, $5}')
  fi
  serial=$(/usr/local/sbin/smartctl -i /dev/"${drive}" | grep "Serial Number" | awk '{print $3}')
  (
  echo ""
  echo "########## SMART status report for ${drive} drive (${brand}: ${serial}) ##########"
  /usr/local/sbin/smartctl -n never -H -A -l error /dev/"${drive}"
  /usr/local/sbin/smartctl -n never -l selftest /dev/"${drive}" | grep "# 1 \|Num" | cut -c6-
  ) >> ${logfile}
done

sed -i '' -e '/smartctl 6.*/d' ${logfile}
sed -i '' -e '/smartctl 5.*/d' ${logfile}
sed -i '' -e '/smartctl 4.*/d' ${logfile}
sed -i '' -e '/Copyright/d' ${logfile}
sed -i '' -e '/=== START OF READ/d' ${logfile}
sed -i '' -e '/SMART Attributes Data/d' ${logfile}
sed -i '' -e '/Vendor Specific SMART/d' ${logfile}
sed -i '' -e '/SMART Error Log Version/d' ${logfile}

echo "</pre>" >> ${logfile}

### Send report ###
if [ -z "${email}" ]; then
  echo "No email address specified, information available in ${logfile}"
else
#  sendmail -t < ${logfile}
  sendmail ${email} < ${logfile}
  rm ${logfile}
fi
