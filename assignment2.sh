#!/bin/bash
set -euo pipefail

# Function to print section headers
section() {
    echo -e "\n\033[1;34m===== $1 =====\033[0m"
}

# Function to handle errors
error_handler() {
    echo -e "\033[1;31mERROR: $1\033[0m" >&2
    exit 1
}

# Network Configuration
configure_network() {
    section "Configuring Network"
    local netplan_file="/etc/netplan/00-installer-config.yaml"
    local expected_ip="192.168.16.21/24"

    # Backup existing netplan file
    cp "$netplan_file" "${netplan_file}.bak"

    # Update netplan configuration
    if ! grep -q "$expected_ip" "$netplan_file"; then
        echo "Updating network configuration..."
        sudo sed -i "/addresses:/s/\[.*\]/\[${expected_ip}\/24\]/" "$netplan_file" || 
            error_handler "Failed to update netplan config"
        netplan apply || error_handler "Failed to apply netplan changes"
    fi

    # Update /etc/hosts
    sudo sed -i '/server1/s/[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/192.168.16.21/' /etc/hosts
}

# Install required packages
install_packages() {
    section "Installing Packages"
    local packages=("apache2" "squid")
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "Installing $pkg..."
            sudo apt-get install -y --assume-yes "$pkg" || error_handler "Failed to install $pkg"
            sudo systemctl enable "$pkg" || error_handler "Failed to enable $pkg"
            sudo systemctl start "$pkg" || error_handler "Failed to start $pkg"
        fi
    done
}

# User management functions
create_user() {
    local username=$1
    section "Configuring User: $username"
    
    # Create user if not exists
    if ! id "$username" &>/dev/null; then
        echo "Creating user $username..."
        sudo useradd -m -s /bin/bash "$username" || error_handler "Failed to create user $username"
    fi

    # Create SSH directory
    local ssh_dir="/home/$username/.ssh"
    sudo mkdir -p "$ssh_dir" || error_handler "Failed to create .ssh directory"
    sudo chown "$username:$username" "$ssh_dir"
    sudo chmod 700 "$ssh_dir"

    # Generate SSH keys
    for key_type in rsa ed25519; do
        local key_file="$ssh_dir/id_$key_type"
        if [ ! -f "$key_file" ]; then
            echo "Generating $key_type key for $username..."
            sudo -u "$username" ssh-keygen -t "$key_type" -f "$key_file" -N "" -q || 
                error_handler "Failed to generate $key_type key"
            sudo -u "$username" cat "${key_file}.pub" >> "$ssh_dir/authorized_keys" || 
                error_handler "Failed to add public key"
        fi
    done

    # Special handling for dennis
    if [ "$username" == "dennis" ]; then
        echo "Configuring sudo access for dennis..."
        sudo usermod -aG sudo dennis || error_handler "Failed to add dennis to sudo group"
        
        # Add special public key
        local special_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
        if ! grep -q "$special_key" "$ssh_dir/authorized_keys"; then
            echo "Adding special key for dennis..."
            echo "$special_key" | sudo tee -a "$ssh_dir/authorized_keys" >/dev/null
        fi
    fi

    # Set permissions
    sudo chown "$username:$username" "$ssh_dir/authorized_keys"
    sudo chmod 600 "$ssh_dir/authorized_keys"
}

main() {
    # Update package lists
    section "Updating Package Lists"
    sudo apt-get update -q || error_handler "Failed to update package lists"

    # Configure network
    configure_network

    # Install required packages
    install_packages

    # Create users
    local users=("dennis" "aubrey" "captain" "snibbles" "brownie" 
                 "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")
    
    for user in "${users[@]}"; do
        create_user "$user"
    done

    section "Configuration Complete"
    echo -e "\033[1;32mAll configurations applied successfully!\033[0m"
}

# Execute main function
main
