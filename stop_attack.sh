#!/bin/bash

echo "[*] Stopping attack processes..."

# === Kill dnsmasq process (used for DHCP/DNS) ===
sudo pkill -f "dnsmasq.*dnsmasq_attack.conf" && \
    echo "[+] dnsmasq terminated" || \
    echo "[-] dnsmasq not found"

# === Kill hostapd-wpe process (used for fake access point) ===
sudo pkill -f "hostapd-wpe" && \
    echo "[+] hostapd-wpe terminated" || \
    echo "[-] hostapd-wpe not found"

# === Kill mitmproxy process (used for HTTPS interception) ===
sudo pkill -f "mitmproxy" && \
    echo "[+] mitmproxy terminated" || \
    echo "[-] mitmproxy not found"

# === Kill the Flask-based captive portal (identified via script path) ===
sudo pkill -f "server_captive_portal.py" && \
    echo "[+] captive portal terminated" || \
    echo "[-] captive portal not found"

# === Optional: Reset iptables rules to default ===
echo "[*] Resetting iptables rules..."
sudo iptables -F         # Flush all default (filter) table rules
sudo iptables -t nat -F  # Flush all NAT table rules
sudo iptables -X         # Delete any user-defined chains
echo "[+] iptables restored to default state"

echo "[✓] All processes terminated (if they were running)"
