#!/usr/bin/env bash
trap '' TERM HUP INT
VERBOSE=false
NAME_SET=false
IP_SET=false
HOSTENTRY_SET=false
HOST_NAME=""
IP_ADDRESS=""
ENTRY_NAME=""
ENTRY_IP=""
LAN_INTERFACE="ens3"

verbose_echo() {
    if [ "$VERBOSE" = true ]; then
        echo "$@"
    fi
}

log_change() {
    logger -t "configure-host" "$1"
    verbose_echo "$1"
}

update_hostname() {
    local current_hostname
    current_hostname=$(hostname)
    if [ "$current_hostname" = "$HOST_NAME" ]; then
        verbose_echo "Hostname is already set to $HOST_NAME. No changes needed."
        return 0
    fi
    echo "$HOST_NAME" | sudo tee /etc/hostname > /dev/null
    if grep -q "127.0.1.1" /etc/hosts; then
        sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$HOST_NAME/" /etc/hosts
    else
        echo -e "127.0.1.1\t$HOST_NAME" | sudo tee -a /etc/hosts > /dev/null
    fi
    sudo hostname "$HOST_NAME"
    log_change "Hostname changed from $current_hostname to $HOST_NAME"
    return 0
}

update_ip() {
    local current_ip
    current_ip=$(ip addr show "$LAN_INTERFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+')
    if [ "$current_ip" = "$IP_ADDRESS" ]; then
        verbose_echo "IP Address is already set to $IP_ADDRESS. No changes needed."
    else
        local netplan_file
        netplan_file=$(find /etc/netplan -name "*.yaml" | head -1)
        if [ -z "$netplan_file" ]; then
            echo "Error: No netplan configuration file found."
            return 1
        fi
        sudo cp "$netplan_file" "${netplan_file}.bak"
        if grep -q "$LAN_INTERFACE" "$netplan_file"; then
            sudo sed -i "/\s*$LAN_INTERFACE:/,/^\s*[^[:space:]]/ s/addresses:.*/addresses: [$IP_ADDRESS\/24]/" "$netplan_file"
        else
            echo "  $LAN_INTERFACE:" | sudo tee -a "$netplan_file" > /dev/null
            echo "    addresses: [$IP_ADDRESS/24]" | sudo tee -a "$netplan_file" > /dev/null
        fi
        sudo netplan apply
        verbose_echo "IP address changed from $current_ip to $IP_ADDRESS."
        log_change "IP address changed from $current_ip to $IP_ADDRESS"
    fi
    if [ -z "$HOST_NAME" ]; then
        HOST_NAME=$(hostname)
    fi
    update_host_entry "$HOST_NAME" "$IP_ADDRESS"
    return 0
}

update_host_entry() {
    local name="$1"
    local ip="$2"
    if grep -qE "\b$name\b" /etc/hosts; then
        sudo sed -i -E "s/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+$name\b/$ip\t$name/" /etc/hosts
        verbose_echo "Updated host entry for $name to $ip."
    else
        echo -e "$ip\t$name" | sudo tee -a /etc/hosts > /dev/null
        verbose_echo "Added host entry: $name with IP $ip."
    fi
    log_change "Host entry updated/added: $name with IP $ip"
    return 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -verbose)
            VERBOSE=true
            shift
            ;;
        -name)
            if [[ -n "$2" ]]; then
                NAME_SET=true
                HOST_NAME="$2"
                shift 2
            else
                echo "Error: -name requires a hostname"
                exit 1
            fi
            ;;
        -ip)
            if [[ -n "$2" ]]; then
                IP_SET=true
                IP_ADDRESS="$2"
                shift 2
            else
                echo "Error: -ip requires an IP address"
                exit 1
            fi
            ;;
        -hostentry)
            if [[ -n "$2" && -n "$3" ]]; then
                HOSTENTRY_SET=true
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

if [ "$NAME_SET" = true ]; then
    update_hostname
fi
if [ "$IP_SET" = true ]; then
    update_ip
fi
if [ "$HOSTENTRY_SET" = true ]; then
    update_host_entry "$ENTRY_NAME" "$ENTRY_IP"
fi
if [ "$NAME_SET" = false ] && [ "$IP_SET" = false ] && [ "$HOSTENTRY_SET" = false ] && [ "$VERBOSE" = true ]; then
    echo "No action specified. Use -name, -ip, or -hostentry."
fi
exit 0
