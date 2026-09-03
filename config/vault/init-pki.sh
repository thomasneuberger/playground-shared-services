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
echo ""
echo "Checking if PKI is already initialized..."
if vault secrets list | grep -q "pki/"; then
    echo "✓ PKI already initialized, checking roles..."
    
    # Verify roles exist
    ROLES_OK=true
    for role in server-cert client-cert service-cert; do
        if ! vault read "pki_int/roles/$role" > /dev/null 2>&1; then
            echo "⚠ Missing role: $role"
            ROLES_OK=false
        fi
    done
    
    if [ "$ROLES_OK" = true ]; then
        echo "✓ All roles exist"
        exit 0
    else
        echo "⚠ Some roles are missing, will create them..."
    fi
else
    echo "⚠ PKI not initialized, initializing now..."
fi

echo ""
echo "Initializing Vault PKI Engine..."
echo "================================================"

# Enable PKI secrets engine if not already enabled
if ! vault secrets list | grep -q "pki/"; then
    echo "1. Enabling PKI secrets engine..."
    vault secrets enable -path=pki pki
    echo "   ✓ Root PKI enabled"
else
    echo "1. Root PKI already enabled"
fi

# Tune the PKI secrets engine
echo "2. Configuring PKI max lease TTL..."
vault secrets tune -max-lease-ttl=${PKI_TTL:-87600h} pki
echo "   ✓ Tuned to ${PKI_TTL:-87600h}"

# Generate root CA
echo "3. Generating root CA certificate..."
vault write -field=certificate pki/root/generate/internal \
    common_name="${PKI_COMMON_NAME:-Shared Services Root CA}" \
    organization="${PKI_ORG:-Shared Services}" \
    ttl=${PKI_TTL:-87600h} \
    key_bits=4096 \
    exclude_cn_from_sans=true > /vault/certs/root_ca.crt

if [ ! -s /vault/certs/root_ca.crt ]; then
    echo "ERROR: Failed to generate root CA certificate"
    exit 1
fi

echo "   ✓ Root CA generated"

# Configure CA and CRL URLs
echo "4. Configuring CA and CRL URLs..."
vault write pki/config/urls \
    issuing_certificates="http://vault:8200/v1/pki/ca" \
    crl_distribution_points="http://vault:8200/v1/pki/crl" > /dev/null
echo "   ✓ URLs configured"

# Enable intermediate PKI if not already enabled
echo "5. Enabling intermediate PKI secrets engine..."
if ! vault secrets list | grep -q "pki_int/"; then
    vault secrets enable -path=pki_int pki
    echo "   ✓ Intermediate PKI enabled"
else
    echo "   ✓ Intermediate PKI already enabled"
fi

# Tune intermediate PKI
echo "6. Configuring intermediate PKI max lease TTL..."
vault secrets tune -max-lease-ttl=43800h pki_int
echo "   ✓ Tuned to 43800h"

# Generate intermediate CSR
echo "7. Generating intermediate CA CSR..."
vault write -field=csr pki_int/intermediate/generate/internal \
    common_name="${PKI_COMMON_NAME:-Shared Services Intermediate CA}" \
    organization="${PKI_ORG:-Shared Services}" \
    key_bits=4096 \
    exclude_cn_from_sans=true > /tmp/intermediate.csr

if [ ! -s /tmp/intermediate.csr ]; then
    echo "ERROR: Failed to generate intermediate CSR"
    exit 1
fi

echo "   ✓ CSR generated"

# Sign intermediate certificate with root CA
echo "8. Signing intermediate certificate..."
vault write -field=certificate pki/root/sign-intermediate \
    csr=@/tmp/intermediate.csr \
    format=pem_bundle \
    ttl=43800h > /tmp/intermediate_cert.crt

if [ ! -s /tmp/intermediate_cert.crt ]; then
    echo "ERROR: Failed to sign intermediate certificate"
    rm -f /tmp/intermediate.csr
    exit 1
fi

echo "   ✓ Intermediate certificate signed"

# Set signed certificate
echo "9. Setting signed intermediate certificate..."
vault write pki_int/intermediate/set-signed certificate=@/tmp/intermediate_cert.crt > /dev/null

rm -f /tmp/intermediate.csr /tmp/intermediate_cert.crt
echo "   ✓ Certificate installed"

# Configure intermediate CA URLs
echo "10. Configuring intermediate CA URLs..."
vault write pki_int/config/urls \
    issuing_certificates="http://vault:8200/v1/pki_int/ca" \
    crl_distribution_points="http://vault:8200/v1/pki_int/crl" > /dev/null
echo "   ✓ URLs configured"

# Create a role for server certificates
echo "11. Creating 'server-cert' role..."
vault write pki_int/roles/server-cert \
    allow_any_name=true \
    allow_localhost=true \
    allow_bare_domains=true \
    allow_ip_sans=true \
    server_flag=true \
    client_flag=false \
    max_ttl=8760h \
    ttl=8760h \
    key_bits=2048 > /dev/null
echo "   ✓ Server-cert role created"

# Create a role for client certificates
echo "12. Creating 'client-cert' role..."
vault write pki_int/roles/client-cert \
    allow_any_name=true \
    enforce_hostnames=false \
    server_flag=false \
    client_flag=true \
    max_ttl=8760h \
    ttl=8760h \
    key_bits=2048 > /dev/null
echo "   ✓ Client-cert role created"

# Create a role for service certificates (both server and client)
echo "13. Creating 'service-cert' role..."
vault write pki_int/roles/service-cert \
    allow_any_name=true \
    allow_localhost=true \
    allow_bare_domains=true \
    allow_ip_sans=true \
    server_flag=true \
    client_flag=true \
    max_ttl=8760h \
    ttl=8760h \
    key_bits=2048 > /dev/null
echo "   ✓ Service-cert role created"

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
