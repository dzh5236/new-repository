#!/bin/bash

# assignment2.sh - Server Configuration Script
# This script configures a target server with specified network settings, 
# software installations, and user accounts.

# Function to print section headers
print_header() {
    echo -e "\n\033[1;34m======== $1 ========\033[0m"
}

# Function to print success messages
print_success() {
    echo -e "\033[0;32m✓ $1\033[0m"
}

# Function to print info messages
print_info() {
    echo -e "\033[0;36mℹ $1\033[0m"
}

# Function to print error messages
print_error() {
    echo -e "\033[0;31m✗ ERROR: $1\033[0m"
}

# Function to check if command was successful
check_status() {
    if [ $1 -ne 0 ]; then
        print_error "$2"
        exit 1
    fi
}

# Check if script is running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# ========= Network Configuration =========
print_header "Network Configuration"

# Get the name of the network interface connected to 192.168.16.0/24 network
lan_interface=$(ip -br addr | grep -v "mgmt" | grep -v "lo" | awk '{print $1}')

if [ -z "$lan_interface" ]; then
    print_error "Could not determine the network interface"
    exit 1
fi

print_info "Detected network interface: $lan_interface"

# Create or update netplan configuration
netplan_file="/etc/netplan/01-netcfg.yaml"

# Backup netplan config if it exists
if [ -f "$netplan_file" ]; then
    cp "$netplan_file" "${netplan_file}.bak"
    print_info "Backed up existing netplan configuration"
fi

# Get current network configuration
current_ip=$(ip -4 addr show $lan_interface 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [ "$current_ip" == "192.168.16.21" ]; then
    print_info "IP address already configured correctly as 192.168.16.21"
else
    print_info "Current IP: $current_ip. Changing to 192.168.16.21"
    
    # Create new netplan configuration
    cat > "$netplan_file" << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $lan_interface:
      dhcp4: no
      addresses: [192.168.16.21/24]
      gateway4: 192.168.16.2
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF

    # Apply the new network configuration
    netplan apply
    check_status $? "Failed to apply netplan configuration"
    print_success "Network configuration updated and applied"
fi

# Update /etc/hosts file
hostname=$(hostname)
if grep -q "$hostname" /etc/hosts; then
    # Update existing entry
    sed -i "s/.*$hostname/192.168.16.21    $hostname/" /etc/hosts
    print_success "Updated /etc/hosts entry for $hostname"
else
    # Add new entry
    echo "192.168.16.21    $hostname" >> /etc/hosts
    print_success "Added $hostname to /etc/hosts"
fi

# ========= Software Installation =========
print_header "Software Installation"

# Update package lists
print_info "Updating package lists..."
apt-get update -q
check_status $? "Failed to update package lists"

# Install Apache2
if dpkg -l | grep -q apache2; then
    print_info "Apache2 is already installed"
else
    print_info "Installing Apache2..."
    apt-get install -y apache2 > /dev/null 2>&1
    check_status $? "Failed to install Apache2"
    print_success "Apache2 installed successfully"
fi

# Ensure Apache2 is running
systemctl is-active --quiet apache2
if [ $? -ne 0 ]; then
    print_info "Starting Apache2 service..."
    systemctl enable --now apache2
    check_status $? "Failed to start Apache2 service"
    print_success "Apache2 service started and enabled"
else
    print_info "Apache2 service is already running"
fi

# Install Squid
if dpkg -l | grep -q squid; then
    print_info "Squid is already installed"
else
    print_info "Installing Squid..."
    apt-get install -y squid > /dev/null 2>&1
    check_status $? "Failed to install Squid"
    print_success "Squid installed successfully"
fi

# Ensure Squid is running
systemctl is-active --quiet squid
if [ $? -ne 0 ]; then
    print_info "Starting Squid service..."
    systemctl enable --now squid
    check_status $? "Failed to start Squid service"
    print_success "Squid service started and enabled"
else
    print_info "Squid service is already running"
fi

# ========= User Account Configuration =========
print_header "User Account Configuration"

# List of users to create
users=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")

# Dennis's extra public key
dennis_pubkey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

# Create users and set up SSH keys
for user in "${users[@]}"; do
    # Check if user exists
    if id "$user" &>/dev/null; then
        print_info "User $user already exists"
    else
        # Create user with home directory and bash shell
        useradd -m -s /bin/bash "$user"
        check_status $? "Failed to create user $user"
        print_success "Created user $user"
    fi
    
    # Set up SSH directory and permissions
    user_home=$(eval echo ~$user)
    ssh_dir="$user_home/.ssh"
    auth_keys="$ssh_dir/authorized_keys"
    
    # Create .ssh directory if it doesn't exist
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        check_status $? "Failed to create SSH directory for $user"
        chown "$user:$user" "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
    
    # Create authorized_keys file if it doesn't exist
    if [ ! -f "$auth_keys" ]; then
        touch "$auth_keys"
        check_status $? "Failed to create authorized_keys for $user"
        chown "$user:$user" "$auth_keys"
        chmod 600 "$auth_keys"
    fi
    
    # Generate RSA key if it doesn't exist
    if [ ! -f "$ssh_dir/id_rsa" ]; then
        print_info "Generating RSA key for $user..."
        sudo -u "$user" ssh-keygen -t rsa -b 2048 -f "$ssh_dir/id_rsa" -N "" > /dev/null 2>&1
        check_status $? "Failed to generate RSA key for $user"
        # Add public key to authorized_keys
        cat "$ssh_dir/id_rsa.pub" >> "$auth_keys"
        print_success "Generated RSA key for $user"
    else
        print_info "RSA key already exists for $user"
    fi
    
    # Generate ed25519 key if it doesn't exist
    if [ ! -f "$ssh_dir/id_ed25519" ]; then
        print_info "Generating ED25519 key for $user..."
        sudo -u "$user" ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" > /dev/null 2>&1
        check_status $? "Failed to generate ED25519 key for $user"
        # Add public key to authorized_keys
        cat "$ssh_dir/id_ed25519.pub" >> "$auth_keys"
        print_success "Generated ED25519 key for $user"
    else
        print_info "ED25519 key already exists for $user"
    fi
    
    # Add Dennis's extra public key if this is Dennis
    if [ "$user" == "dennis" ]; then
        if ! grep -q "$dennis_pubkey" "$auth_keys"; then
            echo "$dennis_pubkey" >> "$auth_keys"
            print_success "Added extra public key to dennis's authorized_keys"
        else
            print_info "Dennis's extra public key already present"
        fi
        
        # Add Dennis to sudo group
        if ! groups dennis | grep -q sudo; then
            usermod -aG sudo dennis
            check_status $? "Failed to add dennis to sudo group"
            print_success "Dennis added to sudo group"
        else
            print_info "Dennis is already in sudo group"
        fi
    fi
    
    # Ensure proper ownership and permissions
    chown -R "$user:$user" "$ssh_dir"
    chmod 700 "$ssh_dir"
    chmod 600 "$auth_keys"
done

print_header "Configuration Complete"
print_success "Server has been configured successfully according to requirements"

# Display network configuration summary
ip_addr=$(ip -4 addr show $lan_interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
print_info "Current IP Address: $ip_addr"
print_info "Apache2 Status: $(systemctl is-active apache2)"
print_info "Squid Status: $(systemctl is-active squid)"
print_info "All users created and configured with SSH keys"

exit 0
