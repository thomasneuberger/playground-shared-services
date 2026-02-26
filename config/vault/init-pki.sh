#!/bin/sh
set -e

echo "================================================"
echo "   Vault PKI Initialization Script"
echo "================================================"

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
until vault status > /dev/null 2>&1; do
    echo "  Waiting for Vault..."
    sleep 2
done
echo "✓ Vault is ready"

# Check if PKI is already initialized
if vault secrets list | grep -q "pki/"; then
    echo "✓ PKI already initialized, skipping setup"
    exit 0
fi

echo ""
echo "Initializing Vault PKI Engine..."
echo "================================================"

# Enable PKI secrets engine at pki/
echo "1. Enabling PKI secrets engine..."
vault secrets enable -path=pki pki

# Tune the PKI secrets engine
echo "2. Configuring PKI max lease TTL..."
vault secrets tune -max-lease-ttl=${PKI_TTL:-87600h} pki

# Generate root CA
echo "3. Generating root CA certificate..."
vault write -format=json pki/root/generate/internal \
    common_name="${PKI_COMMON_NAME:-Shared Services Root CA}" \
    organization="${PKI_ORG:-Shared Services}" \
    ttl=${PKI_TTL:-87600h} \
    key_bits=4096 \
    exclude_cn_from_sans=true \
    > /tmp/root_ca.json

# Extract and save root CA certificate
echo "4. Extracting root CA certificate..."
cat /tmp/root_ca.json | grep -o '"certificate":"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g' > /vault/certs/root_ca.crt
echo "✓ Root CA certificate saved to /vault/certs/root_ca.crt"

# Configure CA and CRL URLs
echo "5. Configuring CA and CRL URLs..."
vault write pki/config/urls \
    issuing_certificates="http://vault:8200/v1/pki/ca" \
    crl_distribution_points="http://vault:8200/v1/pki/crl"

# Enable intermediate PKI
echo "6. Enabling intermediate PKI secrets engine..."
vault secrets enable -path=pki_int pki

# Tune intermediate PKI
echo "7. Configuring intermediate PKI max lease TTL..."
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate intermediate CSR
echo "8. Generating intermediate CA CSR..."
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="${PKI_COMMON_NAME:-Shared Services Intermediate CA}" \
    organization="${PKI_ORG:-Shared Services}" \
    key_bits=4096 \
    exclude_cn_from_sans=true \
    > /tmp/pki_int_csr.json

CSR=$(cat /tmp/pki_int_csr.json | grep -o '"csr":"[^"]*"' | cut -d'"' -f4)

# Sign intermediate certificate with root CA
echo "9. Signing intermediate certificate..."
vault write -format=json pki/root/sign-intermediate \
    csr="$CSR" \
    format=pem_bundle \
    ttl=43800h \
    > /tmp/signed_certificate.json

CERT=$(cat /tmp/signed_certificate.json | grep -o '"certificate":"[^"]*"' | cut -d'"' -f4)

# Set signed certificate
echo "10. Setting signed intermediate certificate..."
echo "$CERT" | sed 's/\\n/\n/g' | vault write pki_int/intermediate/set-signed certificate=-

# Configure intermediate CA URLs
echo "11. Configuring intermediate CA URLs..."
vault write pki_int/config/urls \
    issuing_certificates="http://vault:8200/v1/pki_int/ca" \
    crl_distribution_points="http://vault:8200/v1/pki_int/crl"

# Create a role for server certificates
echo "12. Creating 'server-cert' role..."
vault write pki_int/roles/server-cert \
    allowed_domains="localhost,*.local,*.svc,*.svc.cluster.local" \
    allow_subdomains=true \
    allow_localhost=true \
    allow_bare_domains=true \
    allow_ip_sans=true \
    server_flag=true \
    client_flag=false \
    max_ttl=8760h \
    ttl=8760h \
    key_bits=2048

# Create a role for client certificates
echo "13. Creating 'client-cert' role..."
vault write pki_int/roles/client-cert \
    allow_any_name=true \
    enforce_hostnames=false \
    server_flag=false \
    client_flag=true \
    max_ttl=8760h \
    ttl=8760h \
    key_bits=2048

# Create a role for service certificates (both server and client)
echo "14. Creating 'service-cert' role..."
vault write pki_int/roles/service-cert \
    allowed_domains="localhost,*.local,*.svc,*.svc.cluster.local" \
    allow_subdomains=true \
    allow_localhost=true \
    allow_bare_domains=true \
    allow_ip_sans=true \
    server_flag=true \
    client_flag=true \
    max_ttl=8760h \
    ttl=8760h \
    key_bits=2048

echo ""
echo "================================================"
echo "✓ Vault PKI initialization completed!"
echo "================================================"
echo ""
echo "Available roles:"
echo "  - server-cert  : Server certificates (HTTPS, TLS)"
echo "  - client-cert  : Client certificates (mTLS)"
echo "  - service-cert : Service certificates (both server & client)"
echo ""
echo "Root CA certificate: /vault/certs/root_ca.crt"
echo "================================================"
