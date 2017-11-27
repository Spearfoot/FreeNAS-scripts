#!/bin/sh

# Display current temperature of CPU(s) and all SMART-enabled drives

# Optionally uses IPMI to report temperatures of the system CPU(s)
#
# If IPMI is disabled (see 'use_ipmi' below) then the script uses
# sysctl to report the CPU temperatures. To use IPMI, you must
# provide the IPMI host, user name, and user password file.

# Full path to 'smartctl' program:
smartctl=/usr/local/sbin/smartctl

# IPMI support: set to a postive value to use IPMI for CPU temp
# reporting, set to zero to disable IPMI and use 'sysctl' instead:
use_ipmi=0

# IP address or DNS-resolvable hostname of IPMI server:
ipmihost=192.168.1.x

# IPMI username:
ipmiuser=root

# IPMI password file. This is a file containing the IPMI user's password
# on a single line and should have 0600 permissions:
ipmipwfile=/root/ipmi_password

# Full path to 'ipmitool' program:
ipmitool=/usr/local/bin/ipmitool

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
  gs_smartdrives=""
  gs_drives=$("$smartctl" --scan | awk '{print $1}')

  for gs_drive in $gs_drives; do
    gs_smart_flag=$("$smartctl" -i "$gs_drive" | grep "SMART support is: Enabled" | awk '{print $4}')
    if [ "$gs_smart_flag" = "Enabled" ]; then
      gs_smartdrives="$gs_smartdrives $gs_drive"
    fi
  done
  echo "$gs_smartdrives"
}

drives=$(get_smart_drives)

# end of method 3.

#############################
# CPU temperatures:
#############################
 
if [ "$use_ipmi" -eq 0 ]; then
  cpucores=$(sysctl -n hw.ncpu)
  printf '=== CPU (%s) ===\n' "$cpucores"
  cpucores=$((cpucores - 1))
  for core in $(seq 0 $cpucores); do
    temp=$(sysctl -n dev.cpu."$core".temperature|sed 's/\..*$//g')
    if [ "$temp" -lt 0 ]; then
      temp="--n/a--"
    else
      temp="${temp}C"
    fi
    printf 'CPU %2.2s: %5s\n' "$core" "$temp"
  done
  echo ""
else
  cpucores=$("$ipmitool" -I lanplus -H "$ipmihost" -U "$ipmiuser" -f "$ipmipwfile" sdr elist all | grep -c -i "cpu.*temp")
  
  printf '=== CPU (%s) ===\n' "$cpucores"
  if [ "$cpucores" -eq 1 ]; then
    temp=$("$ipmitool" -I lanplus -H "$ipmihost" -U "$ipmiuser" -f "$ipmipwfile" sdr elist all | grep "CPU Temp" | awk '{print $10}')
    if [ "$temp" -lt 0 ]; then
       temp="-n/a-"
    else
       temp="${temp}C"
    fi
    printf 'CPU %2s: %5s\n' "$core" "$temp"
  else
    for core in $(seq 1 "$cpucores"); do
      temp=$("$ipmitool" -I lanplus -H "$ipmihost" -U "$ipmiuser" -f "$ipmipwfile" sdr elist all | grep "CPU${core} Temp" | awk '{print $10}')
      if [ "$temp" -lt 0 ]; then
         temp="-n/a-"
       else
         temp="${temp}C"
      fi
      printf 'CPU %2s: [%s]\n' "$core" "$temp"
    done
  fi
  echo ""
fi

#############################
# Drive temperatures:
#############################

echo "=== DRIVES ==="
　
# nvme drives may be reported as nvd but for smartctl purposes we need to interrogate /dev/nvme not /dev/nvd
drives=`echo $drives | sed -e "s/nvd/nvme/g"`
　
for drive in $drives; do
  smart_data=$($smartctl -iA /dev/$drive)
　
　
  family=$(echo "$smart_data" | grep "Model Family" | awk '{print $3, $4, $5, $6, $7}' | sed -e 's/[[:space:]]*$//')
  model=$(echo "$smart_data" | grep "Device Model" | awk '{print $3, $4, $5, $6, $7}' | sed -e 's/[[:space:]]*$//')
  if [ -z "$model" ]; then
    model=$(echo "$smart_data" | grep "Model Number:" |  sed -e 's/^Model Number:[[:space:]]*//')
  fi
　
  if [ -z "$family" ]; then
    drive_info="$model"
  else
    drive_info="$family ($model)"
  fi
  if [ -z "$drive_info" ]; then
    vendor=$(echo "$smart_data" | egrep "^Vendor: " | sed -e 's/^Vendor:[[:space:]]*//')
    product=$(echo "$smart_data" | egrep "^Product: " | sed -e 's/Product:[[:space:]]*//')
    drive_info="$vendor $product"
  fi
　
　
  serial=$(echo "$smart_data" | grep -i "Serial Number" | awk '{print $3}')
　
  capacity_text=$(echo "$smart_data" | grep "User Capacity" | sed -E 's/^User Capacity:.*\[([0-9a-zA-Z .]+)\][[:space:]]*$/\1/g')
  if [ -z "$capacity_text" ]; then
   capacity_text=$(echo "$smart_data" | grep "Total NVM Capacity" | sed -E 's/^Total NVM Capacity:.*\[([0-9a-zA-Z .]+)\][[:space:]]*$/\1/g')
  fi
  if [ -z "$capacity_text" ]; then
   capacity_text=$(echo "$smart_data" | grep "Namespace 1 Size/Capacity" | sed -E 's/^Namespace 1 Size\/Capacity:.*\[([0-9a-zA-Z .]+)\][[:space:]]*$/\1/g')
  fi
  capacity_val=$(echo "$capacity_text" | sed -E 's/ .*$//g' | sed -E 's/(\.[1-9]*)0+$/\1/g' | sed -E 's/\.$//g' )
  capacity_unit=$(echo "$capacity_text" | sed -E 's/^.* //g')
　
　
  temp=$(echo "$smart_data" | grep "194 Temperature" | awk '{print $10}')
  if [ -z "$temp" ]; then
    temp=$(echo "$smart_data" | grep "190 Airflow_Temperature" | awk '{print $10}')
  fi
  if [ -z "$temp" ]; then
    temp=$(echo "$smart_data" | egrep "^Current Drive Temperature:" | awk '{print $4}')
  fi
  if [ -z "$temp" ]; then
    temp=$(echo "$smart_data" | egrep "^Temperature:" | awk '{print $2}')
  fi
  if [ -z "$temp" ]; then
    temp="-n/a-"
  else
    temp="${temp}C"
  fi
　
  printf '%6.6s: %5s    %5s%-3s    %-20.20s %s\n' "$(basename "$drive")" "$temp" "$capacity_val" "$capacity_unit" "$serial" "$drive_info"
done
