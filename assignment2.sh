#!/bin/bash
set -euo pipefail

echo "=== Checking and Configuring Network ==="

NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
INTERFACE="enp0s8" # Убедитесь, что имя интерфейса верное

# Настройка сети
if ! grep -q "192.168.16.21/24" "$NETPLAN_FILE" || ! grep -q "$INTERFACE" "$NETPLAN_FILE"; then
    echo "Configuring network interface $INTERFACE..."
    cat <<EOF | tee "$NETPLAN_FILE" >/dev/null
network:
    version: 2
    renderer: networkd
    ethernets:
        $INTERFACE:
            addresses: [192.168.16.21/24]
EOF
    if ! netplan apply; then
        echo "Error: Failed to apply netplan configuration!" >&2
        exit 1
    fi
else
    echo "Network is already configured."
fi

echo "=== Updating /etc/hosts ==="
sed -i '/^192\.168\.16\.21/d' /etc/hosts
echo "192.168.16.21 server1" >> /etc/hosts

echo "=== Installing Required Software ==="
if ! apt update; then
    echo "Error: Failed to update package lists!" >&2
    exit 1
fi
apt install -y apache2 squid

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

    # Генерация ключей, если отсутствуют
    if [ ! -f "$SSH_DIR/id_rsa" ]; then
        ssh-keygen -t rsa -f "$SSH_DIR/id_rsa" -N "" -q
    fi
    if [ ! -f "$SSH_DIR/id_ed25519" ]; then
        ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -q
    fi

    # Добавление публичных ключей
    touch "$SSH_DIR/authorized_keys"
    grep -qxF "$(cat "$SSH_DIR/id_rsa.pub")" "$SSH_DIR/authorized_keys" || cat "$SSH_DIR/id_rsa.pub" >> "$SSH_DIR/authorized_keys"
    grep -qxF "$(cat "$SSH_DIR/id_ed25519.pub")" "$SSH_DIR/authorized_keys" || cat "$SSH_DIR/id_ed25519.pub" >> "$SSH_DIR/authorized_keys"

    if [ "$USER" == "dennis" ]; then
        DENNIS_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
        grep -qxF "$DENNIS_KEY" "$SSH_DIR/authorized_keys" || echo "$DENNIS_KEY" >> "$SSH_DIR/authorized_keys"
    fi

    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$USER:$USER" "$SSH_DIR"
done

echo "=== Granting sudo Access to Dennis ==="
if ! groups dennis | grep -q '\bsudo\b'; then
    usermod -aG sudo dennis
else
    echo "User dennis already has sudo access."
fi

echo "=== Configuration Completed ==="
