
# ⚠️ Evil Twin Attack on Eduroam - Credential Harvesting & MITM Exploitation

<p align="center">
  <img src="https://img.shields.io/badge/status-educational-informational?style=flat-square&logo=readthedocs" />
  <img src="https://img.shields.io/badge/platform-WPA2--Enterprise-blue?style=flat-square&logo=linux"/>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square&logo=openaccess"/>
</p>

> 🚨 This repository is for **educational purposes only**. Do not run this attack outside a **legally authorized** and **controlled** environment.

---

## 📘 Overview

This project replicates a full **Evil Twin attack** against Eduroam WPA2-Enterprise networks using:

- ✅ Misconfigured clients with **no RADIUS certificate validation**
- ✅ Full fake AP + credential harvesting with `hostapd-wpe`
- ✅ Automatic DNS/DHCP + HTTP redirection to a **captive portal**
- ✅ TLS interception via `mitmproxy`
- ✅ Offline password cracking of **MS-CHAPv2 hashes**

---

## 📁 Project Structure

```bash
demo_attack_eduroam/
├── attack_eduroam.sh                # 🔧 Master setup script (downloads deps, sets configs)
├── start_attack.sh                  # Starts AP, DNS, iptables, captive portal
├── stop_attack.sh                   # Stops services, resets iptables
├── dnsmasq/
│   ├── dhcp-hosts.conf              # Optional static leases
│   └── dnsmasq_attack.conf          # DHCP + DNS redirection config
├── hostapd-wpe/
│   ├── hostapd-wpe.conf             # Fake AP configuration
│   ├── hostapd-wpe.eap_user         # EAP auth methods (PAP/MSCHAPv2)
│   ├── hostapd-wpe.log              # 🔐 Harvested credentials log
│   ├── hashes.txt                   # MS-CHAPv2 hashes for cracking
│   ├── ca.pem, server.pem, server.key
│   └── certs/                       # Full OpenSSL CA hierarchy
├── html/
│   ├── captive_portal*.html         # Multiple captive portals (per OS)
│   ├── success.html
│   └── src/
│       ├── eduroam-poliba.mobileconfig
│       ├── cert_installer_windows.exe
│       ├── poliba_ca.crt
│       ├── eduroam-logo.png
│       └── mitmproxy_certs/
│           ├── mitmproxy-ca-cert.pem / .p12 / .cer
│           ├── mitmproxy-ca.pem / .p12
│           └── mitmproxy-dhparam.pem
├── server/
│   └── server_captive_portal.py     # Flask server for captive portal
├── scripts/
│   ├── hostapd-wpe_certs_creation.sh 
│   ├── iptables_setup.sh
│   ├── deauth_attack.sh             # Sends deauth frames via aireplay-ng
│   └── hashcrack.sh                 # Uses hashcat with rockyou.txt
└── README.md                        # Project Documentation
```

---

## 🚀 Quick Start

### 1. ⚙️ Initial Setup

```bash
chmod +x attack_eduroam.sh
sudo ./attack_eduroam.sh
```

> This script sets up everything: dependencies, certs, interfaces, config files, services.

### 2. Start the Attack

```bash
sudo ./start_attack.sh
```

### 3. (Optional) Deauth Clients

```bash
sudo ./scripts/deauth_attack.sh
```

### 4. Stop and Clean Up

```bash
sudo ./stop_attack.sh
```

---

## 📝 Credential Logs

- Plaintext credentials (PAP):  
  `hostapd-wpe/hostapd-wpe.log`

- MS-CHAPv2 Hashes (iOS):  
  `hostapd-wpe/hashes.txt`

Crack them with:

```bash
hashcat -m 5500 hostapd-wpe/hashes.txt /usr/share/wordlists/rockyou.txt
```

---

## 📡 Tested Clients

| OS          | Result |
|-------------|--------|
| Android     | ✅ Auto-connect, credentials in clear |
| HarmonyOS   | ✅ Same as Android |
| Windows     | ⚠️ Cert warning, can be bypassed |
| iOS         | ✅ Vulnerable via MS-CHAPv2 bug |
| Ubuntu      | ✅ Manual config vulnerable |
| CAT config  | ❌ Secure - refuses untrusted certs |

---

## 🔐 Certificate Details

Self-signed certificates mimic `eduroam.poliba.it`:

- `server.pem` signed by fake `GEANT OV RSA CA 4`
- Certs generated via `scripts/hostapd-wpe_certs_creation.sh`

---

## 🌐 Captive Portal

Flask server in `server/` serves OS-specific HTML pages and offers fake cert installation.

OS detection is based on user-agent and redirection from DNS/iptables.

---

## 🔍 MITRE ATT&CK Mapping

| Phase             | Technique ID | Description                          |
|------------------|--------------|--------------------------------------|
| Reconnaissance    | T1590.006    | SSID, certs, and config gathering    |
| Adversary-in-Middle | T1557.004 | Fake AP via hostapd-wpe              |
| Credential Access | T1110.002    | Offline password cracking            |
| TLS Interception | T1185        | HTTPS MITM after cert install        |
| Resource Hijack   | T1583.002    | Fake DNS infrastructure (dnsmasq)   |
| Client Access     | T1659        | Deauth attack                        |

---

## 🛡️ Recommendations

- Enforce **RADIUS server cert validation**
- Prefer **EAP-TLS** over EAP-TTLS/PAP
- Enforce **802.11w** (PMF)
- Block rogue APs with continuous monitoring
- Educate users on **certificate warnings**

---

## 👨‍💻 Authors

Team !Halo:
- Raffaele Di Benedetto 
- Fabio De Simone   
- Antonio Nardone  
- Vincenzo Scialanga  
🎓 Politecnico di Bari, MSc Telecommunication Engineering  
🗓️ Academic Year 2024–2025

---

## ⚠️ Disclaimer

> This project is for **educational** and **authorized** use only.  
> Do not deploy or use on real networks without written consent.  
> The authors decline all responsibility for improper use.

