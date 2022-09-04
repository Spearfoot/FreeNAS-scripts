#!/usr/local/bin/perl
###############################################################################
# 
# get-system-temps.pl
# 
# Displays CPU and drive temperatures
# 
# Drive information reported includes the device ID, temperature, capacity, type
# (SDD or HDD), serial number, model, and, if available, the model family.
# 
# Optionally uses IPMI to report CPU temperatures. Otherwise, these are pulled
# from sysctl. IPMI is more accurate in that it reports the temperature of each
# socketed CPU in the system, even on virtualized instances, whereas the CPU 
# temperatures typically aren't available from sysctl in this case.
# 
# Requires the smartmontools, available at: https://www.smartmontools.org/
# 
# Keith Nash, July 2017
# 
###############################################################################

use strict;
use warnings;

# Get system's hostname:

my $hostname = qx(hostname);
chomp($hostname);

# Full path to the smartctl program:

my $smartctl = "/usr/local/sbin/smartctl";

# IPMI setup:

# Toggle IPMI support on or off: 
# 1 = on:   use IPMI
# 0 = off:  use sysctl instead of IPMI 

my $useipmi = 0;

# IPMI username and password file. The password file is a text file with the
# IPMI user's password on the first line. Be sure to set permissions to 0600
# on the password file.
#
# You may not need credentials on some systems. In this case, ignore these
# variables and modify the ipmitool variable below to suit your environment,
# removing the '-I lanplus' and user credential options (-U and -f) as needed.
 
my $ipmiuser = "root";
my $ipmipwfile = "/root/ipmi_password";

# The IPMI host must be either an IP address or a DNS-resolvable hostname. If you
# have multiple systems, leave the variable blank and edit the conditional below 
# to specify the IPMI host according to the host on which you are running the script:

my $ipmihost = "";

if ($useipmi && $ipmihost eq "") 
  {
  if ($hostname =~ /bandit/) 
    {
    $ipmihost="falcon.ipmi.spearfoot.net"
    }
  elsif ($hostname =~ /boomer/)
    {
    $ipmihost="felix.ipmi.spearfoot.net"
    }
  elsif ($hostname =~ /bacon/)  
    {
    $ipmihost="fritz.ipmi.spearfoot.net"
    }
  else
    {
    die "No IPMI host specified!\n"
    }
  }

# Full path to ipmitool program, including options and credentials:

my $ipmitool = "/usr/local/bin/ipmitool -I lanplus -H $ipmihost -U $ipmiuser -f $ipmipwfile";

main();

###############################################################################
# 
# main
# 
###############################################################################
sub main
{
  printf("==========\n\n");

  if ($useipmi) 
    {
    printf("%s (IPMI host: %s)\n\n",$hostname,$ipmihost);
    }
  else
    {
    printf("%s\n\n",$hostname);
    }

  display_cpu_temps();
  display_drive_info();
}

###############################################################################
# 
# display_cpu_temps
# 
###############################################################################
sub display_cpu_temps 
{
  my $temp;
  my $cpucores=0;

  if ($useipmi)
    {
    $cpucores = qx($ipmitool sdr | grep -c -i "cpu.*temp");
    }
  else
    {
    $cpucores = qx(sysctl -n hw.ncpu);
    }

  printf("=== CPU (%d) ===\n",$cpucores);

  if ($useipmi)
    {
    if ($cpucores > 1)
      {
      for (my $core=1; $core <= $cpucores; $core++)
        {
        $temp=qx($ipmitool sdr | grep -i "CPU$core Temp" | awk '{print \$4}');
        chomp($temp);
        printf("CPU %2u: %3sC\n",$core,$temp);
        }
      }
    else
      {
      $temp=qx($ipmitool sdr | grep -i "CPU Temp" | awk '{print \$4}');
      chomp($temp);
      printf("CPU %2u: %3sC\n",1,$temp);
      }
    }
  else
    {
    for (my $core=0; $core < $cpucores; $core++)
      {
      $temp = qx(sysctl -n dev.cpu.$core.temperature);
      $temp =~ s/[^\-[:digit:]\.]//g;
      chomp($temp);
      if ($temp <= 0)
        {
        printf("CPU %2u: -N/A-\n",$core);
        }
      else
        {
        printf("CPU %2u: %3sC\n",$core,$temp);
        }
      }
    }
}

###############################################################################
# 
# display_drive_info
# 
###############################################################################
sub display_drive_info
{
  my $drive_id;
  my $drive_model;
  my $drive_family;
  my $drive_serial;
  my $drive_capacity;
  my $drive_temp;
  my $drive_is_ssd;
  my $drive_family_display;

  printf("\n=== Drives ===\n");

  my @smart_drive_list = get_smart_drives();

  foreach my $drive (@smart_drive_list)
    {
    ($drive_model, $drive_family, $drive_serial, $drive_capacity, $drive_temp, $drive_is_ssd) = get_drive_info($drive);
    
    if ($drive =~ /\/dev\/(.*)/)
      {
      $drive_id = $1;
      }
    else
      {
      $drive_id = $drive;
      }
    
    if ($drive_family eq "")
      {
      $drive_family_display = "";
      }
    else
      {
      $drive_family_display = "(" . $drive_family . ")";
      }
    
    printf("%6.6s: %3uC [%8.8s %s] %-20.20s %s %s\n",
      $drive_id,
      $drive_temp,
      $drive_capacity,
      $drive_is_ssd ? "SSD" : "HDD",
      $drive_serial,
      $drive_model,
      $drive_family_display);
    }
}

###############################################################################
# 
# get_smart_drives
# 
###############################################################################
sub get_smart_drives
{
  my @retval = ();
  my @drive_list = split(" ", qx($smartctl --scan | awk '{print \$1}'));
 
  foreach my $drive (@drive_list)
    {
    my $smart_enabled = qx($smartctl -i $drive | grep "SMART support is: Enabled" | awk '{print \$4}');
    chomp($smart_enabled);
    if ($smart_enabled eq "Enabled") 
      {
      push @retval, $drive;
      }
    }

  return @retval;
}

###############################################################################
# 
# get_drive_info
# 
###############################################################################
sub get_drive_info
{
  my $drive = shift;
  my $smart_data = qx($smartctl -a $drive);

  my $drive_model = "";
  my $drive_family = "";
  my $drive_serial = "";
  my $drive_capacity = "";
  my $drive_temp = 0;
  my $drive_is_ssd = 0;

  $drive_temp = get_drive_temp($drive);

  # Serial number
  if ($smart_data =~ /^Serial Number:\s*(.*)\s/m)
    {
    $drive_serial = $1;
    }

  # Device model
  if ($smart_data =~ /^Device Model:\s*(.*)\s/m)
    {
    $drive_model = $1;
    }

  # Model family
  if ($smart_data =~ /^Model Family:\s*(.*)\s/m)
    {
    $drive_family = $1;
    }

  # User capacity
  if ($smart_data =~ /^User Capacity:.*\[(.*)\]\s/m)
    {
    $drive_capacity = $1;
    }

  # Determine if drive is a SSD
  if ($smart_data =~ /^Rotation Rate:[ ]*Solid State Device/m)
    {
    $drive_is_ssd = 1;
    }
  elsif ($smart_data =~ /^[ 0-9]{3} Unknown_SSD_Attribute/m)
    {
    $drive_is_ssd = 1;
    }
  elsif ($smart_data =~ /^[ 0-9]{3} Wear_Leveling_Count/m)
    {
    $drive_is_ssd = 1;
    }
  elsif ($smart_data =~ /^[ 0-9]{3} Media_Wearout_Indicator/m)
    {
    $drive_is_ssd = 1;
    }
  elsif ($drive_family =~ /SSD/)
    {
    # Model family indicates SSD
    $drive_is_ssd = 1;
    }

  return ($drive_model, $drive_family, $drive_serial, $drive_capacity, $drive_temp, $drive_is_ssd);
}

###############################################################################
# 
# get_drive_temp
# 
###############################################################################
sub get_drive_temp
{
  my $drive = shift;
  my $retval = 0;

  $retval = qx($smartctl -A $drive | grep "194 Temperature" | awk '{print \$10}');

  if (!$retval)
    {
    $retval = qx($smartctl -A $drive | grep "190 Airflow_Temperature" | awk '{print \$10}');
    }

  return $retval;
}


