#!/usr/bin/env bash

# Ignore signals
trap '' TERM HUP INT

# Initialize variables
VERBOSE=false
ACTION=""
HOST_NAME=""
IP_ADDRESS=""
ENTRY_NAME=""
ENTRY_IP=""
LAN_INTERFACE="ens3"  # Default network interface

# Function for verbose output
verbose_echo() {
    if [ "$VERBOSE" = true ]; then
        echo "$@"
    fi
}

# Function to log changes
log_change() {
    logger -t "configure-host" "$1"
    verbose_echo "$1"
}

# Function to update hostname
update_hostname() {
    local current_hostname=$(hostname)
    
    if [ "$current_hostname" = "$HOST_NAME" ]; then
        verbose_echo "Hostname is already set to $HOST_NAME. No changes needed."
        return 0
    fi
    
    # Update /etc/hostname
    echo "$HOST_NAME" | sudo tee /etc/hostname > /dev/null
    
    # Update /etc/hosts for localhost entry
    if grep -q "127.0.1.1" /etc/hosts; then
        sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$HOST_NAME/" /etc/hosts
    else
        echo -e "127.0.1.1\t$HOST_NAME" | sudo tee -a /etc/hosts > /dev/null
    fi
    
    # Apply hostname to running system
    sudo hostname "$HOST_NAME"
    
    log_change "Hostname changed from $current_hostname to $HOST_NAME"
    return 0
}

# Function to update IP address
update_ip() {
    # Check current IP address
    local current_ip=$(ip addr show $LAN_INTERFACE 2>/dev/null | grep -oP 'inet \K[\d.]+')
    
    if [ "$current_ip" = "$IP_ADDRESS" ]; then
        verbose_echo "IP Address is already set to $IP_ADDRESS. No changes needed."
        return 0
    fi
    
    # Update netplan configuration
    local netplan_file=$(find /etc/netplan -name "*.yaml" | head -1)
    
    if [ -z "$netplan_file" ]; then
        echo "Error: No netplan configuration file found."
        return 1
    fi
    
    # Create a backup of the netplan file
    sudo cp "$netplan_file" "${netplan_file}.bak"
    
    # Update or add IP configuration in netplan file
    if grep -q "$LAN_INTERFACE" "$netplan_file"; then
        sudo sed -i "/\s*$LAN_INTERFACE:/,/^\s*[^[:space:]]/ s/addresses:.*/addresses: [$IP_ADDRESS\/24]/" "$netplan_file"
    else
        # This is simplified - real implementation might need to add more structure
        echo "  $LAN_INTERFACE:" | sudo tee -a "$netplan_file" > /dev/null
        echo "    addresses: [$IP_ADDRESS/24]" | sudo tee -a "$netplan_file" > /dev/null
    fi
    
    # Apply the configuration
    sudo netplan apply
    
    # Update /etc/hosts for this host if hostname is set
    if [ -n "$HOST_NAME" ]; then
        update_host_entry "$HOST_NAME" "$IP_ADDRESS"
    fi
    
    log_change "IP address changed from $current_ip to $IP_ADDRESS"
    return 0
}

# Function to update host entry
update_host_entry() {
    local name="$1"
    local ip="$2"
    
    # Check if entry already exists with correct IP
    if grep -q "^$ip\s.*$name" /etc/hosts; then
        verbose_echo "Host entry for $name ($ip) already exists. No changes needed."
        return 0
    fi
    
    # Check if name exists with different IP
    if grep -q "[[:space:]]$name[[:space:]]" /etc/hosts || grep -q "[[:space:]]$name$" /etc/hosts; then
        # Use proper regex syntax for replacement
        sudo sed -i "s/.*[[:space:]]$name\([[:space:]]\|$\)/$ip\t$name/" /etc/hosts
    else
        # Add new entry
        echo -e "$ip\t$name" | sudo tee -a /etc/hosts > /dev/null
    fi
    
    log_change "Added/updated host entry: $name with IP $ip"
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -verbose)
            VERBOSE=true
            shift
            ;;
        -name)
            if [[ -n "$2" ]]; then
                ACTION="name"
                HOST_NAME="$2"
                shift 2
            else
                echo "Error: -name requires a hostname"
                exit 1
            fi
            ;;
        -ip)
            if [[ -n "$2" ]]; then
                ACTION="ip"
                IP_ADDRESS="$2"
                shift 2
            else
                echo "Error: -ip requires an IP address"
                exit 1
            fi
            ;;
        -hostentry)
            if [[ -n "$2" && -n "$3" ]]; then
                ACTION="hostentry"
                ENTRY_NAME="$2"
                ENTRY_IP="$3"
                shift 3
            else
                echo "Error: -hostentry requires a hostname and IP address"
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute requested action
case "$ACTION" in
    "name")
        update_hostname
        ;;
    "ip")
        update_ip
        ;;
    "hostentry")
        update_host_entry "$ENTRY_NAME" "$ENTRY_IP"
        ;;
    *)
        if [ "$VERBOSE" = true ]; then
            echo "No action specified. Use -name, -ip, or -hostentry."
        fi
        exit 0
        ;;
esac

exit 0
