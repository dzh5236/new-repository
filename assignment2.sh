#!/bin/bash

# Netplan file
NETPLAN_FILE="/etc/netplan/*.yaml"

echo "================================"
echo "Checking netplan file."

# Checking if it exists
if [ ! -f "$NETPLAN_FILE" ]; then
    echo "Netplan file not found: $NETPLAN_FILE"
    exit 1
fi

echo "================================"
echo "Netplan file found."

# Checking if interface is already configured
if grep -q "192.168.16.21/24" "$NETPLAN_FILE"; then
    echo "Interface is already configured."
else
    echo "Configuring the interface..."
    # Changing netplan file
    sudo sed -i '/ethernets:/a \        enp0s8:\n          addresses: [192.168.16.21/24]\n          dhcp4: no' "$NETPLAN_FILE"
    # Applying changes
    sudo netplan apply
    if [ $? -eq 0 ]; then
        echo "Netplan applied successfully."
    else
        echo "Failed to apply netplan. Check the configuration."
        exit 1
    fi
    echo "The interface is configured."
fi

echo "================================"
echo "Configuring the Hosts."

# Configure /etc/hosts
HOSTS_FILE="/etc/hosts"
IP="192.168.16.21"
HOSTNAME="server1"

# Check if the entry already exists
if grep -q "$IP $HOSTNAME" "$HOSTS_FILE"; then
    echo "The entry for $HOSTNAME already exists in $HOSTS_FILE."
else
    echo "Adding $HOSTNAME to $HOSTS_FILE..."
    # Add the new entry to /etc/hosts
    echo "$IP $HOSTNAME" | sudo tee -a "$HOSTS_FILE" > /dev/null
    echo "Entry added successfully."
fi

echo "================================"

echo "Installing Apache2"
if command -v apache2 &>/dev/null; then
    echo "Apache2 is already installed."
else
    echo "Installing Apache2..."
    sudo apt-get update
    sudo apt-get install -y apache2
    echo "Apache2 installed successfully."
fi

echo "================================"

echo "Installing Squid"
if command -v squid &>/dev/null; then
    echo "Squid is already installed."
else
    echo "Installing Squid..."
    sudo apt-get install -y squid
    echo "Squid installed successfully."
fi

echo "================================"

echo "Creating users and setting up SSH keys"
USERS=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")
for USER in "${USERS[@]}"; do
    if id "$USER" &>/dev/null; then
        echo "User $USER already exists."
    else
        echo "Creating user $USER..."
        sudo useradd -m -s /bin/bash "$USER"
        echo "User $USER created successfully."
    fi

    echo "================================"
    echo "Creating directories for users"
    USER_HOME="/home/$USER"
    SSH_DIR="$USER_HOME/.ssh"
    sudo mkdir -p "$SSH_DIR"
    sudo chown "$USER:$USER" "$SSH_DIR"
    sudo chmod 700 "$SSH_DIR"
    echo "Directories successfully created"
    echo "================================"

    echo "Creating RSA keys for users"
    RSA_KEY="$SSH_DIR/id_rsa"
    if [ ! -f "$RSA_KEY" ]; then
        echo "Generating RSA key for $USER..."
        sudo -u "$USER" ssh-keygen -t rsa -b 4096 -f "$RSA_KEY" -N ""
        echo "RSA keys successfully created"
    else
        echo "RSA key already exists for $USER."
    fi

    echo "================================"
    echo "Creating ED25519 keys for users"
    ED25519_KEY="$SSH_DIR/id_ed25519"
    if [ ! -f "$ED25519_KEY" ]; then
        echo "Generating ED25519 key for $USER..."
        sudo -u "$USER" ssh-keygen -t ed25519 -f "$ED25519_KEY" -N ""
        echo "ED25519 keys successfully created"
    else
        echo "ED25519 key already exists for $USER."
    fi

    echo "================================"
    echo "Setting up authorized_keys"
    RSA_PUB_KEY="$SSH_DIR/id_rsa.pub"
    ED25519_PUB_KEY="$SSH_DIR/id_ed25519.pub"
    if [ ! -f "$SSH_DIR/authorized_keys" ]; then
        sudo touch "$SSH_DIR/authorized_keys"
        sudo chown "$USER:$USER" "$SSH_DIR/authorized_keys"
        sudo chmod 600 "$SSH_DIR/authorized_keys"
    fi
    if ! grep -q "$(cat "$RSA_PUB_KEY")" "$SSH_DIR/authorized_keys"; then
        cat "$RSA_PUB_KEY" | sudo tee -a "$SSH_DIR/authorized_keys" > /dev/null
    fi
    if ! grep -q "$(cat "$ED25519_PUB_KEY")" "$SSH_DIR/authorized_keys"; then
        cat "$ED25519_PUB_KEY" | sudo tee -a "$SSH_DIR/authorized_keys" > /dev/null
    fi
    echo "authorized_keys setup complete"
    echo "================================"
done
