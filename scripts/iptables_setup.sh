#!/bin/bash

# Network interfaces
INTERNET_IFACE="eth0"   # Interface connected to the Internet
HOTSPOT_IFACE="wlan0"   # Interface clients connect to
CAPTIVE_IP="10.0.0.1"   # IP address of the captive portal server, DNS, DHCP and proxy

echo "[*] Setting IP address on wlan0"
ip addr add $CAPTIVE_IP/24 dev $HOTSPOT_IFACE

echo "[*] Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[*] Flushing existing iptables rules..."
iptables -F              # Flush default FILTER chain
iptables -t nat -F       # Flush NAT chain
iptables -X              # Delete any user-defined chains

echo "[*] Setting restrictive default policies (blocks everything except default OUTPUT)..."
iptables -P INPUT DROP    # Block all incoming traffic by default
iptables -P FORWARD DROP  # Block all forwarding traffic by default
iptables -P OUTPUT ACCEPT # Allow all outgoing traffic by default (server can access the internet)

echo "[*] Enabling NAT for internet access (if server acts as a router)..."
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE

echo "[*] Allowing loopback traffic (localhost)..."
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

echo "[*] Allowing established and related connections (for general functionality)..."
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[*] Allowing essential traffic for captive portal and dnsmasq on $HOTSPOT_IFACE..."
# DHCP traffic (UDP server port 67)
iptables -A INPUT -i $HOTSPOT_IFACE -p udp --dport 67 -j ACCEPT   # Dnsmasq receives DHCP requests
iptables -A OUTPUT -o $HOTSPOT_IFACE -p udp --sport 67 -j ACCEPT  # Dnsmasq sends DHCP replies
# DNS traffic (UDP/TCP port 53)
iptables -A INPUT -i $HOTSPOT_IFACE -p udp --dport 53 -j ACCEPT
iptables -A INPUT -i $HOTSPOT_IFACE -p tcp --dport 53 -j ACCEPT
# HTTP/HTTPS traffic for the captive portal (port 80 and 443 on the server itself)
iptables -A INPUT -i $HOTSPOT_IFACE -p tcp --dport 80 -j ACCEPT # ACCEPT HTTP traffic
iptables -A INPUT -i $HOTSPOT_IFACE -p tcp --dport 443 -j DROP # DROP HTTPS traffic

# Allow incoming traffic to mitmproxy port from wlan0
iptables -A INPUT -i $HOTSPOT_IFACE -p tcp --dport 8080 -j ACCEPT

echo "[*] Redirecting all UNAUTHORIZED HTTP traffic to captive portal on port 80..."
# These rules must be the last in the PREROUTING chain for the captive portal.
# The captive portal server inserts rules for authorized IPs (REDIRECT to mitmproxy)
iptables -t nat -A PREROUTING -i $HOTSPOT_IFACE -p tcp --dport 80 -j DNAT --to-destination $CAPTIVE_IP:80

echo "[*] Captive portal setup script completed. Initial rules are active."
