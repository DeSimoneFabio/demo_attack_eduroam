#!/bin/bash

# === 0. Install required frameworks and libraries ===
echo "[*] Installing required frameworks and libraries ..."
sudo apt update

# === 1. Remove bcrypt installed from Debian packages ===
sudo apt remove python3-bcrypt -y

# === 2. Install a specific version of bcrypt via pip ===
# --break-system-packages is required on modern Debian-based systems to override default protections
sudo pip3 install bcrypt==4.0.1 --break-system-packages
sudo pip3 install passlib --break-system-packages

# === 3. Define list of required system packages ===
REQUIRED_PACKAGES=(
    gnome-terminal      # To launch terminal windows (used in automation)
    hostapd-wpe         # Fake AP with EAP support
    dnsmasq             # DHCP and DNS server
    mitmproxy           # Intercept HTTPS traffic
    python3             # Required for running scripts
    net-tools           # Networking utilities (ifconfig, etc.)
    iptables            # For configuring firewall and NAT rules
    python3-pip         # Python package manager
    aircrack-ng         # For deauthentication attacks
)

# === 4. Install each required package ===
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    echo "[*] Checking/installing package: $pkg ..."
    sudo apt install -y "$pkg" || echo "[-] Error installing $pkg"
done

# === 5. Run mitmdump once to generate default mitmproxy certificates ===
echo "[*] Initial run of mitmdump to generate certificates ..."
mitmdump --quiet --set block_global=false --mode transparent --listen-port 8080 --listen-host 127.0.0.1 --quit-after 1

# === 6. Install Flask globally (used for captive portal backend) ===
echo "[*] Installing Flask (globally)..."
sudo pip3 install flask --break-system-packages || echo "[-] Error installing Flask. Check pip3."

# === 7. Create target directory under /opt if not already existing ===
echo "[*] Creating /opt directory ..."
cd /
mkdir -p /opt
if [ $? -ne 0 ]; then
    echo "[-] Error: Failed to create /opt directory. Check permissions."
    exit 1
fi

# === 8. Change to the /opt directory ===
echo "[*] Changing to /opt directory ..."
cd /opt || { echo "[-] Error changing directory."; exit 1; }

# === 9. Clone GitHub repository if it hasn't been cloned already ===
if [ -d ".git" ]; then
    echo "[*] Repository already cloned. Skipping clone."
else
    echo "[*] Cloning GitHub repository..."
    git clone https://github.com/raffaeledb01/demo_attack_eduroam || {
        echo "[-] Error: Could not clone GitHub repository."
        exit 1
    }
fi

# === 10. Copy mitmproxy certificates to root user’s ~/.mitmproxy folder ===
echo "[*] Copying mitmproxy certificates to ~/.mitmproxy ..."
cd --  # Go back to the root user's home directory
mkdir -p .mitmproxy
cp /opt/demo_attack_eduroam/html/src/mitmproxy_certs/* /root/.mitmproxy/ 2>/dev/null || echo "[-] Certificates not copied."

# === 11. Make sure all scripts are executable ===
echo "[*] Setting executable permissions for attack scripts ..."
chmod +x /opt/demo_attack_eduroam/start_attack.sh
chmod +x /opt/demo_attack_eduroam/stop_attack.sh
chmod +x /opt/demo_attack_eduroam/scripts/iptables_setup.sh
chmod +x /opt/demo_attack_eduroam/scripts/deauth_attack.sh
chmod +x /opt/demo_attack_eduroam/scripts/hashcrack.sh

# === 12. Start the main attack script ===
echo "[*] Launching the attack script ..."
cd /opt/demo_attack_eduroam
sudo systemctl stop apache2  # Stop Apache if it's running to free up ports used by Flask/mitmproxy
#sudo systemctl disable apache2  # Optional: prevent Apache from auto-starting in the future
#sudo bash /opt/demo_attack_eduroam/start_attack.sh  # Uncomment to start attack script automatically

echo "[*] Script completed."
