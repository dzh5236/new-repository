#!/bin/bash

# This script runs the configure-host.sh script from the current directory to modify 
# 2 servers and update the local /etc/hosts file

# Initialize variables
VERBOSE=""

# Check for verbose flag
if [[ "$1" == "-verbose" ]]; then
  VERBOSE="-verbose"
  echo "Running in verbose mode"
fi

# Function to check command status and exit if failed
check_status() {
  if [[ $1 -ne 0 ]]; then
    echo "Error: $2 failed with exit code $1" >&2
    exit $1
  elif [[ -n "$VERBOSE" ]]; then
    echo "Success: $2"
  fi
}

# Ensure configure-host.sh exists and is executable
if [[ ! -f "./configure-host.sh" ]]; then
  echo "Error: configure-host.sh not found in current directory" >&2
  exit 1
fi

chmod +x ./configure-host.sh
check_status $? "Setting execute permission on configure-host.sh"

# Configure server1 (loghost)
echo "Configuring server1..."
scp ./configure-host.sh remoteadmin@server1-mgmt:/root
check_status $? "Copying configure-host.sh to server1"

ssh remoteadmin@server1-mgmt -- "chmod +x /root/configure-host.sh"
check_status $? "Setting execute permission on server1"

ssh remoteadmin@server1-mgmt -- "/root/configure-host.sh $VERBOSE -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4"
check_status $? "Running configure-host.sh on server1"

# Configure server2 (webhost)
echo "Configuring server2..."
scp ./configure-host.sh remoteadmin@server2-mgmt:/root
check_status $? "Copying configure-host.sh to server2"

ssh remoteadmin@server2-mgmt -- "chmod +x /root/configure-host.sh"
check_status $? "Setting execute permission on server2"

ssh remoteadmin@server2-mgmt -- "/root/configure-host.sh $VERBOSE -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3"
check_status $? "Running configure-host.sh on server2"

# Update local hosts file
echo "Updating local hosts file..."
sudo ./configure-host.sh $VERBOSE -hostentry loghost 192.168.16.3
check_status $? "Adding loghost entry to local hosts file"

sudo ./configure-host.sh $VERBOSE -hostentry webhost 192.168.16.4
check_status $? "Adding webhost entry to local hosts file"

echo "Configuration complete!"
exit 0
