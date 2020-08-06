#!/bin/sh

### Parameters ###

# Specify your email address here:
email=""

# Full path to 'smartctl' program:
smartctl=/usr/local/sbin/smartctl

freenashost=$(hostname -s | tr '[:lower:]' '[:upper:]')
boundary="===== MIME boundary; FreeNAS server ${freenashost} ====="
logfile="smart_report.tmp"
subject="SMART Status Report for ${freenashost}"
tempWarn=40
tempCrit=45
sectorsCrit=10
testAgeWarn=1
warnSymbol="?"
critSymbol="!"
Drive_count=0
SATA_count=0
SAS_count=0
Drive_list=""
SATA_list=""
SAS_list=""

# Get list of SMART-enabled drives
get_smart_drives()
{
  gs_drives=$("$smartctl" --scan | awk '{print $1}')
  for gs_drive in $gs_drives; do
    gs_smart_flag=$("$smartctl" -i "$gs_drive" | grep -E "SMART support is:[[:blank:]]+Enabled" | awk '{print $4}')
    if [ "$gs_smart_flag" = "Enabled" ]; then
      Drive_list="$Drive_list $gs_drive"
      Drive_count=$((Drive_count + 1))
    fi
  done
}

# Get list of SATA disks, including older drives that only report an ATA version
get_sata_drives()
{
  for drive in $Drive_list; do
    lFound=0
    gsata_smart_flag=$("$smartctl" -i "$drive" | grep -E "SATA Version is:[[:blank:]]" | awk '{print $4}')
    if [ "$gsata_smart_flag" = "SATA" ]; then
      lFound=$((lFound + 1))
    else
      gsata_smart_flag=$("$smartctl" -i "$drive" | grep -E "ATA Version is:[[:blank:]]" | awk '{print $1}')
      if [ "$gsata_smart_flag" = "ATA" ]; then  
        lFound=$((lFound + 1))
      fi
    fi
    if [ $lFound -gt 0 ]; then  
      SATA_list="$SATA_list $drive"
      SATA_count=$((SATA_count + 1))
    fi
  done
}

# Get list of SAS disks
get_sas_drives()
{
  for drive in $Drive_list; do
    gsas_smart_flag=$("$smartctl" -i "$drive" | grep -E "Transport protocol:[[:blank:]]+SAS" | awk '{print $3}')
    if [ "$gsas_smart_flag" = "SAS" ]; then
      SAS_list="$SAS_list $drive"
      SAS_count=$((SAS_count + 1))
    fi
  done
}

### Fetch drive lists ###
get_smart_drives
get_sata_drives
get_sas_drives

### Set email headers ###
printf "%s\n" "To: ${email}
Subject: ${subject}
Mime-Version: 1.0
Content-Type: multipart/mixed; boundary=\"$boundary\"

--${boundary}
Content-Type: text/html; charset=\"US-ASCII\"
Content-Transfer-Encoding: 7bit
Content-Disposition: inline
<html><head></head><body><pre style=\"font-size:14px; white-space:pre\">" > ${logfile}

if [ $Drive_count -eq 0 ]; then
  echo "##### No SMART-enabled disks found on this system #####" >> "$logfile"
fi

###### Summary for SATA drives ######
if [ $SATA_count -gt 0 ]; then
  (
   echo "########## SMART status report summary for all SATA drives on server ${freenashost} ##########"
   echo ""
   echo "+------+------------------------+----+------+-----+-----+-------+-------+--------+------+----------+------+-----------+----+"
   echo "|Device|Serial                  |Temp| Power|Start|Spin |ReAlloc|Current|Offline |Seek  |Total     |High  |    Command|Last|"
   echo "|      |Number                  |    | On   |Stop |Retry|Sectors|Pending|Uncorrec|Errors|Seeks     |Fly   |    Timeout|Test|"
   echo "|      |                        |    | Hours|Count|Count|       |Sectors|Sectors |      |          |Writes|    Count  |Age |"
   echo "+------+------------------------+----+------+-----+-----+-------+-------+--------+------+----------+------+-----------+----+"
  ) >> "$logfile"
  
  ###### Detail information for each SATA drive ######
  for drive in $SATA_list; do
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
      if (temp > tempWarn || temp > tempCrit) temp=temp"*"
      if (reAlloc > 0 || reAlloc > sectorsCrit) reAlloc=reAlloc"*"
      if (pending > 0 || pending > sectorsCrit) pending=pending"*"
      if (offlineUnc > 0 || offlineUnc > sectorsCrit) offlineUnc=offlineUnc"*"
      if (testAge > testAgeWarn) testAge=testAge"*"
      if (hiFlyWr == "") hiFlyWr="N/A";
      if (cmdTimeout == "") cmdTimeout="N/A";
      printf "|%-6s|%-24s|%-4s|%6s|%5s|%5s|%7s|%7s|%8s|%6s|%10s|%6s|%11s|%4s|\n",
        device, serial, temp, onHours, startStop, spinRetry, reAlloc, pending, offlineUnc,
        seekErrors, totalSeeks, hiFlyWr, cmdTimeout, testAge;
      }'
    ) >> "$logfile"
  done
  (
    echo "+------+------------------------+----+------+-----+-----+-------+-------+--------+------+----------+------+-----------+----+"
  ) >> "$logfile"
fi

###### Summary for SAS drives ######
if [ $SAS_count -gt 0 ]; then
  (
    if [ $SATA_count -gt 0 ]; then
      echo ""
    fi
  
    echo "########## SMART status report summary for all SAS drives on server ${freenashost} ##########"
    echo ""
    echo "+------+------------------------+----+-----+------+------+------+------+------+------+"
    echo "|Device|Serial                  |Temp|Start|Load  |Defect|Uncorr|Uncorr|Uncorr|Non   |"
    echo "|      |Number                  |    |Stop |Unload|List  |Read  |Write |Verify|Medium|"
    echo "|      |                        |    |Count|Count |Elems |Errors|Errors|Errors|Errors|"
    echo "+------+------------------------+----+-----+------+------+------+------+------+------+"
  ) >> "$logfile"
  
  ###### Detail information for each SAS drive ######
  for drive in $SAS_list; do
    (
    devid=$(basename "$drive")
    "$smartctl" -a "$drive" | \
    awk -v device="$devid" -v tempWarn="$tempWarn" -v tempCrit="$tempCrit" \
    -v warnSymbol="$warnSymbol" -v critSymbol="$critSymbol" '\
    /Serial number:/{serial=$3}
    /Current Drive Temperature:/{temp=$4} \
    /start-stop cycles:/{startStop=$4} \
    /load-unload cycles:/{loadUnload=$4} \
    /grown defect list:/{defectList=$6} \
    /read:/{readErrors=$8} \
    /write:/{writeErrors=$8} \
    /verify:/{verifyErrors=$8} \
    /Non-medium error count:/{nonMediumErrors=$4} \
    END {
      if (temp > tempCrit)
      device=device " " critSymbol;
    else if (temp > tempWarn)
        device=device " " warnSymbol;
      printf "|%-6s|%-24s| %3s|%5s|%6s|%6s|%6s|%6s|%6s|%6s|\n",
      device, serial, temp, startStop, loadUnload, defectList, \
      readErrors, writeErrors, verifyErrors, nonMediumErrors;
     }'
    ) >> "$logfile"
  done
  (
    echo "+------+------------------------+----+-----+------+------+------+------+------+------+"
  ) >> "$logfile"
fi

if [ $SATA_count -gt 0 ] || [ $SAS_count -gt 0 ]; then
 
  ###### Emit SATA drive information ######
  for drive in $SATA_list; do
    vendor=$("$smartctl" -i "$drive" | grep "Vendor:" | awk '{print $NF}')
    if [ -z "$vendor" ]; then
      dfamily=$("$smartctl" -i "$drive" | grep "Model Family" | awk '{print $3, $4, $5, $6, $7}' | sed -e 's/[[:space:]]*$//')
      dmodel=$("$smartctl" -i "$drive" | grep "Device Model" | awk '{print $3, $4, $5, $6, $7}' | sed -e 's/[[:space:]]*$//')
      if [ -z "$dfamily" ]; then
        dinfo=$dmodel
      else
        dinfo="$dfamily ($dmodel)"
      fi
    else
      product=$("$smartctl" -i "$drive" | grep "Product:" | awk '{print $NF}')
      revision=$("$smartctl" -i "$drive" | grep "Revision:" | awk '{print $NF}')
      dinfo="$vendor $product $revision"
    fi
    serial=$("$smartctl" -i "$drive" | grep "Serial Number" | awk '{print $3}')
    (
    echo ""
    echo "########## SATA drive $drive Serial: $serial"
    echo "########## ${dinfo}" 
    "$smartctl" -n never -H -A -l error "$drive"
    "$smartctl" -n never -l selftest "$drive" | grep "# 1 \\|Num" | cut -c6-
    ) >> "$logfile"
  done
  
  ###### Emit SAS drive information ######
  for drive in $SAS_list; do
    devid=$(basename "$drive")
    brand=$("$smartctl" -i "$drive" | grep "Product" | sed "s/^.* //")
    serial=$("$smartctl" -i "$drive" | grep "Serial number" | sed "s/^.* //")
    (
    echo ""
    echo "########## SMART status for SAS drive $drive $serial (${brand}) ##########"
    "$smartctl" -n never -H -A -l error "$drive"
    "$smartctl" -n never -l selftest "$drive" | grep "# 1 \\|Num" | cut -c6-
    ) >> "$logfile"
  done
fi

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
