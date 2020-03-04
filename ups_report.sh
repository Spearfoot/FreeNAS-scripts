#!/bin/sh

# Send UPS report to designated email address
# Reference: http://networkupstools.org/docs/developer-guide.chunked/apas01.html

### Parameters ###

# Specify your email address here:
email=""

# Set to a value greater than zero to include all available UPSC
# variables in the report:
senddetail=0

freenashost=$(hostname -s)
freenashostuc=$(hostname -s | tr '[:lower:]' '[:upper:]')
boundary="===== MIME boundary; FreeNAS server ${freenashost} ====="
logfile="/tmp/ups_report.tmp"
subject="UPS Status Report for ${freenashostuc}"

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

# Get a list of all ups devices installed on the system:

upslist=$(upsc -l "${freenashost}")

### Set email body ###
(
 date "+Time: %Y-%m-%d %H:%M:%S"
 echo ""
 for ups in $upslist; do
   ups_type=$(upsc "${ups}" device.type 2> /dev/null | tr '[:lower:]' '[:upper:]')
   ups_mfr=$(upsc "${ups}" ups.mfr 2> /dev/null)
   ups_model=$(upsc "${ups}" ups.model 2> /dev/null)
   ups_serial=$(upsc "${ups}" ups.serial 2> /dev/null)
   ups_status=$(upsc "${ups}" ups.status 2> /dev/null)
   ups_load=$(upsc "${ups}" ups.load 2> /dev/null)
   ups_realpower=$(upsc "${ups}" ups.realpower 2> /dev/null)
   ups_realpowernominal=$(upsc "${ups}" ups.realpower.nominal 2> /dev/null)
   ups_batterycharge=$(upsc "${ups}" battery.charge 2> /dev/null)
   ups_batteryruntime=$(upsc "${ups}" battery.runtime 2> /dev/null)
   ups_batteryvoltage=$(upsc "${ups}" battery.voltage 2> /dev/null)
   ups_inputvoltage=$(upsc "${ups}" input.voltage 2> /dev/null)
   ups_outputvoltage=$(upsc "${ups}" output.voltage 2> /dev/null)
   printf "=== %s %s, model %s, serial number %s\n\n" "${ups_mfr}" "${ups_type}" "${ups_model}" "${ups_serial} ==="
   echo "Name: ${ups}"
   echo "Status: ${ups_status}"
   echo "Output Load: ${ups_load}%"
   if [ ! -z "${ups_realpower}" ]; then
     echo "Real Power: ${ups_realpower}W"
   fi
   if [ ! -z "${ups_realpowernominal}" ]; then
     echo "Real Power: ${ups_realpowernominal}W (nominal)"
   fi
   if [ ! -z "${ups_inputvoltage}" ]; then
     echo "Input Voltage: ${ups_inputvoltage}V"
   fi
   if [ ! -z "${ups_outputvoltage}" ]; then
     echo "Output Voltage: ${ups_outputvoltage}V"
   fi
   echo "Battery Runtime: ${ups_batteryruntime}s"
   echo "Battery Charge: ${ups_batterycharge}%"
   echo "Battery Voltage: ${ups_batteryvoltage}V"
   echo ""
   if [ $senddetail -gt 0 ]; then
     echo "=== ALL AVAILABLE UPS VARIABLES ==="
     upsc "${ups}"
     echo ""
   fi
 done
) >> ${logfile}

printf "%s\n" "</pre></body></html>
--${boundary}--" >> ${logfile}

### Send report ###
if [ -z "${email}" ]; then
  echo "No email address specified, information available in ${logfile}"
else
  sendmail -t -oi < ${logfile}
  rm ${logfile}
fi

