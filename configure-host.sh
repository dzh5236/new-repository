#!/bin/bash

# System Configuration Script
# Manages hostname, IP address, and hosts file entries

echo "=== Starting system configuration script ==="

# Verify root privileges
echo "Checking for root privileges..."
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root" >&2
    exit 1
fi
echo "✓ Root privileges confirmed"

# Configuration variables
declare -A CONFIG_ARGS
VERBOSE_MODE=0
HOSTNAME_FILE="/etc/hostname"
HOSTS_FILE="/etc/hosts"
NETPLAN_CONFIG="/etc/netplan/10-lxc.yaml"

# Setup interruption handling
echo "Configuring script interruption handlers..."
cleanup_interrupt() {
    echo "! Script interrupted - performing cleanup..."
    exit 1
}
trap cleanup_interrupt TERM HUP INT
echo "✓ Interruption handlers configured"

# Enhanced logging function
log_event() {
    local log_message="$1"
    logger -t "system_config" "$log_message"
    [[ $VERBOSE_MODE -eq 1 ]] && echo "LOG: $log_message"
}

# Verify system dependencies
echo "Checking for required system commands..."
verify_dependencies() {
    local required_commands=("ip" "hostnamectl" "netplan" "logger" "sed")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "ERROR: Required command '$cmd' not found in system PATH"
            exit 1
        fi
        echo "✓ Found required command: $cmd"
    done
    echo "✓ All system dependencies verified"
}

# Hostname configuration function
set_system_hostname() {
    local new_hostname="$1"
    echo "Checking current hostname..."
    local current_hostname=$(cat "$HOSTNAME_FILE" 2>/dev/null)
    
    if [[ "$current_hostname" != "$new_hostname" ]]; then
        echo "Updating system hostname from '$current_hostname' to '$new_hostname'"
        
        echo "Writing new hostname to $HOSTNAME_FILE..."
        if ! echo "$new_hostname" > "$HOSTNAME_FILE"; then
            echo "ERROR: Failed to update $HOSTNAME_FILE"
            return 1
        fi
        echo "✓ Hostname file updated"
        
        echo "Applying hostname change system-wide..."
        if ! hostnamectl set-hostname "$new_hostname"; then
            echo "ERROR: Failed to update hostname via hostnamectl"
            return 1
        fi
        echo "✓ System hostname updated"
        
        echo "Updating hosts file reference..."
        sed -i "/127.0.1.1/c\127.0.1.1\t$new_hostname" "$HOSTS_FILE"
        echo "✓ Hosts file reference updated"
        
        log_event "Hostname changed to $new_hostname"
    else
        echo "Hostname already configured as '$new_hostname' - no changes needed"
    fi
}

# IP address configuration
configure_network_ip() {
    local new_ip="$1"
    echo "Identifying default network interface..."
    local network_interface=$(ip -o -4 route show to default | awk '{print $5}')
    echo "Found interface: $network_interface"
    
    echo "Checking current IP address..."
    local current_ip=$(ip -o -4 addr show dev "$network_interface" | awk '{print $4}' | cut -d'/' -f1)
    
    if [[ "$current_ip" != "$new_ip" ]]; then
        echo "Updating IP configuration from $current_ip to $new_ip"
        
        echo "Creating netplan configuration backup..."
        cp "$NETPLAN_CONFIG" "${NETPLAN_CONFIG}.backup"
        echo "✓ Backup created at ${NETPLAN_CONFIG}.backup"
        
        if command -v yq &>/dev/null; then
            echo "Using yq for YAML configuration..."
            yq e ".network.ethernets.$network_interface.addresses = [\"$new_ip/24\"]" -i "$NETPLAN_CONFIG"
            echo "✓ YAML configuration updated using yq"
        else
            echo "Notice: Using basic sed for YAML modification (install yq for better handling)"
            sed -i "/$network_interface:/,/addresses:/s/addresses: .*/addresses: [$new_ip\/24]/" "$NETPLAN_CONFIG"
            echo "✓ YAML configuration updated using sed"
        fi
        
        echo "Applying network configuration..."
        if ! netplan apply; then
            echo "ERROR: Network configuration failed - restoring backup"
            mv "${NETPLAN_CONFIG}.backup" "$NETPLAN_CONFIG"
            return 1
        fi
        echo "✓ Network configuration successfully applied"
    else
        echo "Network already configured with IP $new_ip - no changes needed"
    fi
}

# Hosts file management
update_hosts_file() {
    local host_entry_name="$1"
    local host_entry_ip="$2"
    echo "Preparing to update hosts file entry for $host_entry_name ($host_entry_ip)"
    
    local sanitized_name=$(printf '%s\n' "$host_entry_name" | sed 's:[][\/.^$*]:\\&:g')
    
    echo "Checking for existing entries..."
    if grep -q "$sanitized_name" "$HOSTS_FILE"; then
        echo "Found existing entry - removing old version..."
        sed -i "/$sanitized_name$/d" "$HOSTS_FILE"
        echo "✓ Old entry removed"
    else
        echo "No existing entry found - proceeding with new entry"
    fi
    
    echo "Adding new hosts file entry..."
    echo -e "$host_entry_ip\t$host_entry_name" >> "$HOSTS_FILE"
    echo "✓ New entry added: $host_entry_ip $host_entry_name"
    
    log_event "Updated hosts file: $host_entry_ip $host_entry_name"
}

# Argument processing
process_arguments() {
    echo "Processing command line arguments..."
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -verbose) 
                VERBOSE_MODE=1
                echo "Verbose mode enabled"
                ;;
            -name) 
                CONFIG_ARGS[name]="$2"
                echo "Hostname set to: $2"
                shift 
                ;;
            -ip) 
                CONFIG_ARGS[ip]="$2"
                echo "IP address set to: $2"
                shift 
                ;;
            -hostentry) 
                CONFIG_ARGS[hostentry_name]="$2" 
                CONFIG_ARGS[hostentry_ip]="$3"
                echo "Hosts entry set to: $2 $3"
                shift 2 
                ;;
            *) 
                echo "ERROR: Invalid option: $1" >&2
                exit 1 
                ;;
        esac
        shift
    done
    echo "✓ All arguments processed"
}

# Main execution flow
echo "=== Beginning configuration process ==="
verify_dependencies
process_arguments "$@"

if [[ -n "${CONFIG_ARGS[name]}" ]]; then
    echo "--- Processing hostname configuration ---"
    set_system_hostname "${CONFIG_ARGS[name]}"
else
    echo "No hostname change requested - skipping"
fi

if [[ -n "${CONFIG_ARGS[ip]}" ]]; then
    echo "--- Processing IP address configuration ---"
    configure_network_ip "${CONFIG_ARGS[ip]}"
else
    echo "No IP address change requested - skipping"
fi

if [[ -n "${CONFIG_ARGS[hostentry_name]}" ]]; then
    echo "--- Processing hosts file update ---"
    update_hosts_file "${CONFIG_ARGS[hostentry_name]}" "${CONFIG_ARGS[hostentry_ip]}"
else
    echo "No hosts file changes requested - skipping"
fi

echo "=== System configuration completed successfully ==="
log_event "System configuration completed"
exit 0
