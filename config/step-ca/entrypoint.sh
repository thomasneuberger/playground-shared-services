#!/bin/bash
set -e

STEPPATH=${STEPPATH:=/home/step}
CA_NAME=${CA_NAME:-SharedServices}
CA_DNS=${CA_DNS:-localhost,127.0.0.1,step-ca}
STEP_CA_PASSWORD=${STEP_CA_PASSWORD:-password123}

echo "=== Step CA Bootstrap ==="

# Check if already initialized
if [ -f "$STEPPATH/config/ca.json" ]; then
    echo "Step CA bereits initialisiert. Starte Daemon..."
    exec step-ca "$STEPPATH/config/ca.json" --password-file <(echo -n "$STEP_CA_PASSWORD")
fi

echo "Initialisiere neue Step CA..."

# Initialize Step CA (non-interactive)
mkdir -p "$STEPPATH"
cd "$STEPPATH"

# Generate root and intermediate certificates
step certificate create \
  --profile root-ca \
  --insecure \
  --password-file <(echo -n "$STEP_CA_PASSWORD") \
  "$CA_NAME Root CA" \
  "$STEPPATH/certs/root_ca.crt" \
  "$STEPPATH/secrets/root_ca_key"

step certificate create \
  --profile intermediate-ca \
  --ca "$STEPPATH/certs/root_ca.crt" \
  --ca-key "$STEPPATH/secrets/root_ca_key" \
  --insecure \
  --password-file <(echo -n "$STEP_CA_PASSWORD") \
  "$CA_NAME Intermediate CA" \
  "$STEPPATH/certs/intermediate_ca.crt" \
  "$STEPPATH/secrets/intermediate_ca_key"

# Create config directory
mkdir -p "$STEPPATH/config"
mkdir -p "$STEPPATH/db"

# Copy config template
cat > "$STEPPATH/config/ca.json" << 'EOF'
{
  "root": "/home/step/certs/root_ca.crt",
  "federatedRoots": null,
  "crt": "/home/step/certs/intermediate_ca.crt",
  "key": "/home/step/secrets/intermediate_ca_key",
  "address": ":9000",
  "insecureAddress": "",
  "dnsNames": [
    "localhost",
    "127.0.0.1",
    "step-ca"
  ],
  "logger": {
    "format": "text"
  },
  "db": {
    "type": "badger",
    "dataSource": "/home/step/db"
  },
  "authority": {
    "provisioners": [
      {
        "type": "ACME",
        "name": "acme"
      }
    ]
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3,
    "renegotiation": false
  }
}
EOF

echo "Step CA erfolgreich initialisiert!"
echo ""
echo "Root CA: $STEPPATH/certs/root_ca.crt"
echo "Intermediate CA: $STEPPATH/certs/intermediate_ca.crt"
echo ""

# Start daemon
exec step-ca "$STEPPATH/config/ca.json" --password-file <(echo -n "$STEP_CA_PASSWORD")
