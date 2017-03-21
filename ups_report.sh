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
logfile="/tmp/ups_report.tmp"
subject="UPS Status Report for ${freenashostuc}"

### Set email headers ###
(
 echo "To: ${email}"
 echo "Subject: ${subject}"
 echo "Content-Type: text/html"
 echo "MIME-Version: 1.0"
 printf "\r\n"
) > ${logfile}

# Get a list of all ups devices installed on the system:

upslist=$(upsc -l "${freenashost}")

### Set email body ###
(
 echo "<pre style=\"font-size:14px\">"
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

echo "</pre>" >> ${logfile}

### Send report ###
if [ -z "${email}" ]; then
  echo "No email address specified, information available in ${logfile}"
else
#  sendmail -t < ${logfile}
  sendmail ${email} < ${logfile}
  rm ${logfile}
fi

