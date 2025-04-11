#!/bin/bash

# Script to configure basic host settings
# Ignore TERM, HUP and INT signals
trap "" TERM HUP INT

# Default verbose mode is off
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -verbose)
      VERBOSE=true
      shift
      ;;
    -name)
      if [[ $# -lt 2 ]]; then
        echo "Error: -name option requires a parameter" >&2
        exit 1
      fi
      DESIRED_NAME="$2"
      shift 2
      ;;
    -ip)
      if [[ $# -lt 2 ]]; then
        echo "Error: -ip option requires a parameter" >&2
        exit 1
      fi
      DESIRED_IP="$2"
      shift 2
      ;;
    -hostentry)
      if [[ $# -lt 3 ]]; then
        echo "Error: -hostentry option requires two parameters" >&2
        exit 1
      fi
      ENTRY_NAME="$2"
      ENTRY_IP="$3"
      shift 3
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
  esac
done

# Function to log verbose output
log_verbose() {
  if [[ "$VERBOSE" == true ]]; then
    echo "$1"
  fi
}

# Function to update hostname
update_hostname() {
  local current_hostname=$(hostname)
  
  if [[ "$current_hostname" != "$DESIRED_NAME" ]]; then
    # Update /etc/hostname
    echo "$DESIRED_NAME" > /etc/hostname
    
    # Update /etc/hosts
    sed -i "s/127.0.1.1.*/127.0.1.1\t$DESIRED_NAME/" /etc/hosts
    
    # Apply hostname to running system
    hostname "$DESIRED_NAME"
    
    log_verbose "Hostname changed from $current_hostname to $DESIRED_NAME"
    logger "Hostname changed from $current_hostname to $DESIRED_NAME"
  else
    log_verbose "Hostname is already set to $DESIRED_NAME. No changes needed."
  fi
}

# Function to update IP address
update_ip() {
  local lan_interface=$(ip route | grep default | awk '{print $5}')
  local current_ip=$(ip -4 addr show $lan_interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  
  if [[ "$current_ip" != "$DESIRED_IP" ]]; then
    # Update netplan file
    cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $lan_interface:
      dhcp4: no
      addresses: [$DESIRED_IP/24]
      gateway4: 192.168.16.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
    
    # Apply netplan changes
    netplan apply
    
    # Update /etc/hosts if hostname is set
    if [[ -n "$DESIRED_NAME" ]]; then
      if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t$DESIRED_NAME/" /etc/hosts
      else
        echo "127.0.1.1	$DESIRED_NAME" >> /etc/hosts
      fi
    fi
    
    log_verbose "IP address changed from $current_ip to $DESIRED_IP"
    logger "IP address changed from $current_ip to $DESIRED_IP"
  else
    log_verbose "IP address is already set to $DESIRED_IP. No changes needed."
  fi
}

# Function to update hosts entry
update_hostentry() {
  if grep -q "$ENTRY_NAME" /etc/hosts; then
    # Entry exists, check if IP is correct
    local current_ip=$(grep "$ENTRY_NAME" /etc/hosts | awk '{print $1}')
    
    if [[ "$current_ip" != "$ENTRY_IP" ]]; then
      # Update existing entry
      sed -i "s/.*\s$ENTRY_NAME/$ENTRY_IP\t$ENTRY_NAME/" /etc/hosts
      log_verbose "Updated hosts entry for $ENTRY_NAME from $current_ip to $ENTRY_IP"
      logger "Updated hosts entry for $ENTRY_NAME from $current_ip to $ENTRY_IP"
    else
      log_verbose "Hosts entry for $ENTRY_NAME already has IP $ENTRY_IP. No changes needed."
    fi
  else
    # Add new entry
    echo -e "$ENTRY_IP\t$ENTRY_NAME" >> /etc/hosts
    log_verbose "Added new hosts entry: $ENTRY_IP $ENTRY_NAME"
    logger "Added new hosts entry: $ENTRY_IP $ENTRY_NAME"
  fi
}

# Execute requested operations
if [[ -n "$DESIRED_NAME" ]]; then
  update_hostname
fi

if [[ -n "$DESIRED_IP" ]]; then
  update_ip
fi

if [[ -n "$ENTRY_NAME" && -n "$ENTRY_IP" ]]; then
  update_hostentry
fi

exit 0
