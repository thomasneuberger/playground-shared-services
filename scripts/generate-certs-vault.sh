#!/bin/bash
# Generate certificates using Vault PKI Engine - Linux/macOS Edition

set -e

# Default values
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8201}"
VAULT_TOKEN="${VAULT_TOKEN:-myroot123}"
OUTPUT_DIR="./certs"
ROLE="server-cert"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Help message
show_help() {
    cat << EOF
Vault PKI Certificate Generator

Usage: $0 [OPTIONS]

OPTIONS:
    -d, --domain DOMAIN          Domain name for server certificate
    -c, --common-name NAME       Common name for client certificate
    -i, --ip-sans IPS            Comma-separated IP addresses for SANs
    -r, --role ROLE              Vault PKI role (server-cert, client-cert, service-cert)
    -a, --vault-addr ADDR        Vault address (default: http://localhost:8201)
    -t, --vault-token TOKEN      Vault token (default: \$VAULT_TOKEN or myroot123)
    -o, --output-dir DIR         Output directory (default: ./certs)
    --root-ca                    Export root CA certificate only
    -h, --help                   Show this help message

EXAMPLES:
    # Generate server certificate for localhost
    $0 -d localhost

    # Generate server certificate with IP SAN
    $0 -d myapp.local -i "192.168.1.10,127.0.0.1"

    # Generate client certificate
    $0 -c "user@example.com" -r client-cert

    # Generate service certificate (server + client)
    $0 -d myservice.local -r service-cert

    # Export root CA
    $0 --root-ca

EOF
    exit 0
}

# Parse arguments
EXPORT_ROOT_CA=false
DOMAIN=""
COMMON_NAME=""
IP_SANS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -c|--common-name)
            COMMON_NAME="$2"
            shift 2
            ;;
        -i|--ip-sans)
            IP_SANS="$2"
            shift 2
            ;;
        -r|--role)
            ROLE="$2"
            shift 2
            ;;
        -a|--vault-addr)
            VAULT_ADDR="$2"
            shift 2
            ;;
        -t|--vault-token)
            VAULT_TOKEN="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --root-ca)
            EXPORT_ROOT_CA=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Banner
echo ""
echo "============================================================"
echo "   Vault PKI Certificate Generator"
echo "============================================================"
echo ""

# Set Vault environment
export VAULT_ADDR
export VAULT_TOKEN

# Check if vault CLI is available
if ! command -v vault &> /dev/null; then
    error "Vault CLI not found. Please install it from: https://www.vaultproject.io/downloads"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
info "Output directory: $OUTPUT_DIR"

# Export Root CA only
if [ "$EXPORT_ROOT_CA" = true ]; then
    info "Exporting Root CA certificate..."
    
    ROOT_CA_PATH="$OUTPUT_DIR/root_ca.crt"
    if vault read -field=certificate pki/cert/ca > "$ROOT_CA_PATH"; then
        success "Root CA exported to: $ROOT_CA_PATH"
        echo ""
        info "To trust this CA:"
        echo "  # Linux:"
        echo "  sudo cp $ROOT_CA_PATH /usr/local/share/ca-certificates/"
        echo "  sudo update-ca-certificates"
        echo ""
        echo "  # macOS:"
        echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $ROOT_CA_PATH"
        echo ""
    else
        error "Failed to export root CA"
        exit 1
    fi
    
    exit 0
fi

# Determine what to generate
CERT_NAME=""
CERT_PATH=""

if [ "$ROLE" = "client-cert" ]; then
    if [ -z "$COMMON_NAME" ]; then
        error "Common name is required for client certificates"
        info "Usage: $0 -c \"user@example.com\" -r client-cert"
        exit 1
    fi
    CERT_NAME="$COMMON_NAME"
    CERT_PATH="$OUTPUT_DIR/$(echo $COMMON_NAME | tr '@.' '__')"
else
    if [ -z "$DOMAIN" ]; then
        error "Domain is required for server/service certificates"
        info "Usage: $0 -d \"localhost\""
        exit 1
    fi
    CERT_NAME="$DOMAIN"
    CERT_PATH="$OUTPUT_DIR/$DOMAIN"
fi

info "Certificate Type: $ROLE"
info "Certificate Name: $CERT_NAME"
echo ""

# Build Vault command
VAULT_CMD="vault write -format=json pki_int/issue/$ROLE"

if [ "$ROLE" = "client-cert" ]; then
    VAULT_CMD="$VAULT_CMD common_name=$COMMON_NAME"
else
    VAULT_CMD="$VAULT_CMD common_name=$DOMAIN alt_names=$DOMAIN"
fi

if [ -n "$IP_SANS" ]; then
    VAULT_CMD="$VAULT_CMD ip_sans=$IP_SANS"
fi

VAULT_CMD="$VAULT_CMD ttl=8760h"

# Generate certificate
info "Generating certificate from Vault PKI..."
if RESULT=$($VAULT_CMD 2>&1); then
    # Extract data using jq or grep/sed
    if command -v jq &> /dev/null; then
        CERTIFICATE=$(echo "$RESULT" | jq -r '.data.certificate')
        PRIVATE_KEY=$(echo "$RESULT" | jq -r '.data.private_key')
        CA_CHAIN=$(echo "$RESULT" | jq -r '.data.ca_chain | join("\n")')
        SERIAL=$(echo "$RESULT" | jq -r '.data.serial_number')
    else
        warning "jq not found, using basic parsing"
        CERTIFICATE=$(echo "$RESULT" | grep -o '"certificate":"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g')
        PRIVATE_KEY=$(echo "$RESULT" | grep -o '"private_key":"[^"]*"' | cut -d'"' -f4 | sed 's/\\n/\n/g')
        # This is simplified and may not work perfectly for ca_chain
        CA_CHAIN=$(echo "$RESULT" | grep -o '"ca_chain":\[[^]]*\]' | sed 's/\\n/\n/g')
        SERIAL=$(echo "$RESULT" | grep -o '"serial_number":"[^"]*"' | cut -d'"' -f4)
    fi
    
    # Save files
    echo "$CERTIFICATE" > "${CERT_PATH}.crt"
    success "Certificate saved: ${CERT_PATH}.crt"
    
    echo "$PRIVATE_KEY" > "${CERT_PATH}.key"
    chmod 600 "${CERT_PATH}.key"
    success "Private key saved: ${CERT_PATH}.key"
    
    echo "$CA_CHAIN" > "${CERT_PATH}-ca-chain.crt"
    success "CA chain saved: ${CERT_PATH}-ca-chain.crt"
    
    # Create bundle
    cat "${CERT_PATH}.crt" "${CERT_PATH}-ca-chain.crt" > "${CERT_PATH}-bundle.crt"
    success "Certificate bundle saved: ${CERT_PATH}-bundle.crt"
    
    # Summary
    echo ""
    echo "============================================================"
    success "Certificate generated successfully!"
    echo "============================================================"
    echo ""
    echo -e "${CYAN}Files created:${NC}"
    echo "  Certificate:    ${CERT_PATH}.crt"
    echo "  Private Key:    ${CERT_PATH}.key"
    echo "  CA Chain:       ${CERT_PATH}-ca-chain.crt"
    echo "  Bundle:         ${CERT_PATH}-bundle.crt"
    echo ""
    info "Serial Number: $SERIAL"
    echo ""
    
    # Export Root CA if not exists
    ROOT_CA_PATH="$OUTPUT_DIR/root_ca.crt"
    if [ ! -f "$ROOT_CA_PATH" ]; then
        info "Exporting Root CA certificate..."
        vault read -field=certificate pki/cert/ca > "$ROOT_CA_PATH"
        success "Root CA exported to: $ROOT_CA_PATH"
    fi
    
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Trust the Root CA (if not already done)"
    echo "  2. Use the certificate in your application"
    echo ""
    
else
    error "Failed to generate certificate"
    echo "$RESULT"
    exit 1
fi
