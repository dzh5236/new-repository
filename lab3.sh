
# Process command line arguments
VERBOSE_FLAG=""
if [[ "$1" == "-verbose" ]]; then
  VERBOSE_FLAG="-verbose"
  echo "Running in verbose mode"
fi

# Function to check if host is reachable
check_host() {
  if ! ping -c 1 -W 2 "$1" &> /dev/null; then
    echo "ERROR: Cannot reach host $1. Please ensure the host is up and network is configured."
    return 1
  fi
  return 0
}

# Function to handle errors
handle_error() {
  echo "ERROR: $1"
  exit 1
}

# Basic trap for clean exit
trap 'echo "Script interrupted."; exit 1' INT TERM

# Check if configure-host.sh exists
if [[ ! -f "./configure-host.sh" ]]; then
  handle_error "configure-host.sh script not found in current directory"
fi

# Make sure configure-host.sh is executable
chmod +x ./configure-host.sh || handle_error "Cannot make configure-host.sh executable"

# Verify servers are reachable
echo "Verifying server1-mgmt is reachable..."
check_host server1-mgmt || handle_error "Cannot reach server1-mgmt"

echo "Verifying server2-mgmt is reachable..."
check_host server2-mgmt || handle_error "Cannot reach server2-mgmt"

# Configure server1
echo "Copying configure-host.sh to server1..."
scp configure-host.sh remoteadmin@server1-mgmt:/root/configure-host.sh || handle_error "Failed to copy script to server1-mgmt"

echo "Configuring server1..."
ssh remoteadmin@server1-mgmt -- "chmod +x /root/configure-host.sh && /root/configure-host.sh $VERBOSE_FLAG -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4" || handle_error "Configuration of server1-mgmt failed"

# Configure server2
echo "Copying configure-host.sh to server2..."
scp configure-host.sh remoteadmin@server2-mgmt:/root/configure-host.sh || handle_error "Failed to copy script to server2-mgmt"

echo "Configuring server2..."
ssh remoteadmin@server2-mgmt -- "chmod +x /root/configure-host.sh && /root/configure-host.sh $VERBOSE_FLAG -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3" || handle_error "Configuration of server2-mgmt failed"

# Update local host entries
echo "Updating local /etc/hosts for the two servers..."
sudo ./configure-host.sh $VERBOSE_FLAG -hostentry loghost 192.168.16.3 || handle_error "Failed to update local hosts for loghost"
sudo ./configure-host.sh $VERBOSE_FLAG -hostentry webhost 192.168.16.4 || handle_error "Failed to update local hosts for webhost"

echo "All configurations completed successfully."
exit 0
