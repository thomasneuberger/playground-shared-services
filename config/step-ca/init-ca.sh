#!/bin/bash
# Initialize Step CA Setup
# This script initializes a fresh Step CA installation

set -e

CA_NAME="${CA_NAME:-SharedServices}"
STEPPATH="${STEPPATH:-/home/step}"
STEP_CA_PASSWORD="${STEP_CA_PASSWORD:-}"

if [ -z "$STEP_CA_PASSWORD" ]; then
    echo "ERROR: STEP_CA_PASSWORD environment variable is required"
    exit 1
fi

echo "Initializing Step CA..."
echo "CA Name: $CA_NAME"
echo "STEPPATH: $STEPPATH"

# Create directories
mkdir -p "$STEPPATH/certs"
mkdir -p "$STEPPATH/secrets"
mkdir -p "$STEPPATH/config"
mkdir -p "$STEPPATH/db"

# Generate Root CA
echo "Generating Root CA..."
step certificate create \
    --profile root-ca \
    --force \
    --no-password \
    "$CA_NAME Root CA" \
    "$STEPPATH/certs/root_ca.crt" \
    "$STEPPATH/secrets/root_ca_key" 2>&1

# Generate Intermediate CA
echo "Generating Intermediate CA..."
step certificate create \
    --profile intermediate-ca \
    --ca "$STEPPATH/certs/root_ca.crt" \
    --ca-key "$STEPPATH/secrets/root_ca_key" \
    --ca-password-file <(echo -n "$STEP_CA_PASSWORD") \
    --no-password \
    --force \
    "$CA_NAME Intermediate CA" \
    "$STEPPATH/certs/intermediate_ca.crt" \
    "$STEPPATH/secrets/intermediate_ca_key" 2>&1

# Create CA config
echo "Creating CA configuration..."
cat > "$STEPPATH/config/ca.json" << 'CONFIG'
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
    "format": "text",
    "level": "info"
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
      },
      {
        "type": "JWK",
        "name": "admin",
        "key": {
          "use": "sig",
          "kty": "EC",
          "crv": "P-256",
          "kid": "admin",
          "x": "example",
          "y": "example"
        },
        "encryptedKey": "example"
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
CONFIG

echo "✓ Step CA initialized successfully"
echo ""
echo "Files created:"
echo "  Root CA: $STEPPATH/certs/root_ca.crt"
echo "  Intermediate CA: $STEPPATH/certs/intermediate_ca.crt"
echo "  Config: $STEPPATH/config/ca.json"
echo ""
echo "Next steps:"
echo "  1. Export root certificate: docker cp shared-step-ca:/home/step/certs/root_ca.crt ./certs/"
echo "  2. Import to system trust store"
echo "  3. Generate certificates: ./scripts/generate-certs.sh domain.local"
