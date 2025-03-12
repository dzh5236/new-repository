#!/bin/bash

echo "=== Checking and Configuring Network ==="

NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
if ! grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
    echo "Configuring network interface..."
    sed -i '/addresses:/c\        addresses: [192.168.16.21/24]' "$NETPLAN_FILE"
    netplan apply
else
    echo "Network is already configured."
fi

echo "=== Updating /etc/hosts ==="
sed -i '/server1/d' /etc/hosts
echo "192.168.16.21 server1" >> /etc/hosts

echo "=== Installing Required Software ==="
apt update && apt install -y apache2 squid

echo "=== Creating User Accounts ==="
USERS=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")
for USER in "${USERS[@]}"; do
    if ! id "$USER" &>/dev/null; then
        echo "Creating user $USER..."
        useradd -m -s /bin/bash "$USER"
    else
        echo "User $USER already exists."
    fi
done

echo "=== Configuring SSH Keys ==="
for USER in "${USERS[@]}"; do
    HOME_DIR="/home/$USER"
    SSH_DIR="$HOME_DIR/.ssh"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    ssh-keygen -t rsa -f "$SSH_DIR/id_rsa" -N "" -q
    ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -q

    cat "$SSH_DIR/id_rsa.pub" >> "$SSH_DIR/authorized_keys"
    cat "$SSH_DIR/id_ed25519.pub" >> "$SSH_DIR/authorized_keys"

    if [ "$USER" == "dennis" ]; then
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm" >> "$SSH_DIR/authorized_keys"
    fi

    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$USER:$USER" "$SSH_DIR"
done

echo "=== Granting sudo Access to Dennis ==="
usermod -aG sudo dennis

echo "=== Configuration Completed ==="
