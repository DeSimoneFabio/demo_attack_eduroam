#!/bin/bash

# Change directory to the hostapd-wpe folder where the certificates will be created
cd /opt/demo_attack/hostapd-wpe/

# Generate a 4096-bit private key for the Certificate Authority (CA)
openssl genrsa -out ca.key 4096

# Create a self-signed CA certificate valid for 10 years (3650 days)
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.pem \
-subj "/C=NL/O=GEANT Vereniging/CN=GEANT OV RSA CA 4"

# Generate a 2048-bit private key for the server (fake AP)
openssl genrsa -out server.key 2048

# Create a Certificate Signing Request (CSR) for the server
openssl req -new -key server.key -out server.csr \
-subj "/CN=eduroam.poliba.it"

# Sign the server certificate with the CA, valid for 1 year (365 days)
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
-out server.pem -days 365 -sha256

# Remove the CA private key for security reasons
rm ca.key

# Remove the CA Serial Number (no longer needed)
rm ca.srl

# Remove the server certificate signing request (no longer needed)
rm server.csr

