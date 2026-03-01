#!/usr/bin/env bash
# Generate certificates using Vault PKI Engine - Linux/macOS Edition

set -euo pipefail

# Defaults
DOMAIN=""
COMMON_NAME=""
IP_SANS=""
ROLE="server-cert"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8201}"
VAULT_TOKEN_PARAM=""
OUTPUT_DIR="./certs"
EXPORT_ROOT_CA=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<'EOF'
Vault PKI Certificate Generator (Bash)

Usage:
  ./scripts/generate-certs-vault.sh [OPTIONS]

Options (Bash style):
  -d, --domain DOMAIN
  -c, --common-name NAME
  -i, --ip-sans IPS
  -r, --role ROLE                (server-cert|client-cert|service-cert)
  -a, --vault-addr ADDR
  -t, --vault-token TOKEN
  -o, --output-dir DIR
      --root-ca
  -h, --help

Options (PowerShell-compatible aliases):
  -Domain DOMAIN
  -CommonName NAME
  -IpSans IPS
  -Role ROLE
  -VaultAddr ADDR
  -VaultToken TOKEN
  -OutputDir DIR
  -ExportRootCA

Examples:
  ./scripts/generate-certs-vault.sh -d rabbit.local -i "192.168.178.35"
  ./scripts/generate-certs-vault.sh -Domain rabbit.local -IpSans "192.168.178.35"
  ./scripts/generate-certs-vault.sh -c "user@example.com" -r client-cert
  ./scripts/generate-certs-vault.sh --root-ca
EOF
}

read_token_from_env_file() {
    local env_file=".env"
    if [[ -f "$env_file" ]]; then
        sed -n 's/^VAULT_TOKEN=//p' "$env_file" | head -n 1
    fi
}

require_value() {
    local opt_name="$1"
    local opt_value="${2:-}"
    if [[ -z "$opt_value" ]]; then
        err "Missing value for $opt_name"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain|-Domain)
                require_value "$1" "${2:-}"
                DOMAIN="$2"
                shift 2
                ;;
            -c|--common-name|-CommonName)
                require_value "$1" "${2:-}"
                COMMON_NAME="$2"
                shift 2
                ;;
            -i|--ip-sans|-IpSans)
                require_value "$1" "${2:-}"
                IP_SANS="$2"
                shift 2
                ;;
            -r|--role|-Role)
                require_value "$1" "${2:-}"
                ROLE="$2"
                shift 2
                ;;
            -a|--vault-addr|-VaultAddr)
                require_value "$1" "${2:-}"
                VAULT_ADDR="$2"
                shift 2
                ;;
            -t|--vault-token|-VaultToken)
                require_value "$1" "${2:-}"
                VAULT_TOKEN_PARAM="$2"
                shift 2
                ;;
            -o|--output-dir|-OutputDir)
                require_value "$1" "${2:-}"
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --root-ca|-ExportRootCA)
                EXPORT_ROOT_CA=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

validate_role() {
    case "$ROLE" in
        server-cert|client-cert|service-cert) ;;
        *)
            err "Invalid role '$ROLE'. Use: server-cert, client-cert, service-cert"
            exit 1
            ;;
    esac
}

json_get_string() {
    local filter="$1"
    jq -r "$filter // empty"
}

json_get_array_lines() {
    local filter="$1"
    jq -r "$filter // [] | .[]"
}

echo ""
echo "============================================================"
echo "  Vault PKI Certificate Generator (Bash)"
echo "============================================================"
echo ""

parse_args "$@"
validate_role

if ! command -v vault >/dev/null 2>&1; then
    err "Vault CLI not found. Install from https://www.vaultproject.io/downloads"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    err "jq is required for JSON parsing. Please install jq and retry."
    exit 1
fi

if [[ -n "$VAULT_TOKEN_PARAM" ]]; then
    VAULT_TOKEN="$VAULT_TOKEN_PARAM"
    info "Using provided Vault token"
elif [[ -n "${VAULT_TOKEN:-}" ]]; then
    VAULT_TOKEN="${VAULT_TOKEN}"
    info "Using Vault token from environment variable"
else
    token_from_file="$(read_token_from_env_file || true)"
    if [[ -n "$token_from_file" ]]; then
        VAULT_TOKEN="$token_from_file"
        info "Using Vault token from .env file"
    else
        VAULT_TOKEN="myroot123"
        warn "No VAULT_TOKEN found, using default: myroot123"
    fi
fi

export VAULT_ADDR
export VAULT_TOKEN

mkdir -p "$OUTPUT_DIR"

if [[ "$EXPORT_ROOT_CA" == true ]]; then
    info "Exporting Root CA certificate..."
    root_ca_path="$OUTPUT_DIR/root_ca.crt"
    if vault read -field=certificate pki/cert/ca > "$root_ca_path"; then
        ok "Root CA exported to: $root_ca_path"
        exit 0
    else
        err "Failed to export root CA"
        exit 1
    fi
fi

cert_name=""
cert_path=""

if [[ "$ROLE" == "client-cert" ]]; then
    if [[ -z "$COMMON_NAME" ]]; then
        err "CommonName is required for client certificates"
        info "Usage: ./scripts/generate-certs-vault.sh -CommonName user@example.com -Role client-cert"
        exit 1
    fi
    cert_name="$COMMON_NAME"
    safe_name="${COMMON_NAME//@/_}"
    safe_name="${safe_name//./_}"
    cert_path="$OUTPUT_DIR/$safe_name"
else
    if [[ -z "$DOMAIN" ]]; then
        err "Domain is required for server/service certificates"
        info "Usage: ./scripts/generate-certs-vault.sh -Domain rabbit.local"
        exit 1
    fi
    cert_name="$DOMAIN"
    cert_path="$OUTPUT_DIR/$DOMAIN"
fi

info "Certificate Type: $ROLE"
info "Certificate Name: $cert_name"
echo ""

vault_args=(write -format=json "pki_int/issue/$ROLE")
if [[ "$ROLE" == "client-cert" ]]; then
    vault_args+=("common_name=$COMMON_NAME")
else
    vault_args+=("common_name=$DOMAIN" "alt_names=$DOMAIN")
fi
if [[ -n "$IP_SANS" ]]; then
    vault_args+=("ip_sans=$IP_SANS")
fi
vault_args+=("ttl=8760h")

info "Generating certificate from Vault PKI..."
if ! result_json="$(vault "${vault_args[@]}" 2>&1)"; then
    err "Failed to generate certificate:"
    echo "$result_json"
    exit 1
fi

certificate="$(echo "$result_json" | json_get_string '.data.certificate')"
private_key="$(echo "$result_json" | json_get_string '.data.private_key')"
serial_number="$(echo "$result_json" | json_get_string '.data.serial_number')"
expiration="$(echo "$result_json" | json_get_string '.data.expiration')"

if [[ -z "$certificate" || -z "$private_key" ]]; then
    err "Vault response missing certificate or private key"
    exit 1
fi

ca_chain_lines="$(echo "$result_json" | json_get_array_lines '.data.ca_chain')"

cert_file="${cert_path}.crt"
key_file="${cert_path}.key"
ca_chain_file="${cert_path}-ca-chain.crt"
bundle_file="${cert_path}-bundle.crt"

{
    printf '%s\n' "$certificate"
    if [[ -n "$ca_chain_lines" ]]; then
        printf '%s\n' "$ca_chain_lines"
    fi
} > "$cert_file"
ok "Certificate with CA chain saved: $cert_file"

printf '%s\n' "$private_key" > "$key_file"
chmod 600 "$key_file" 2>/dev/null || true
ok "Private key saved: $key_file"

if [[ -n "$ca_chain_lines" ]]; then
    printf '%s\n' "$ca_chain_lines" > "$ca_chain_file"
else
    : > "$ca_chain_file"
fi
ok "CA chain saved: $ca_chain_file"

cp "$cert_file" "$bundle_file"
ok "Certificate bundle saved: $bundle_file"

root_ca_path="$OUTPUT_DIR/root_ca.crt"
if [[ ! -f "$root_ca_path" ]]; then
    info "Exporting Root CA certificate..."
    if vault read -field=certificate pki/cert/ca > "$root_ca_path"; then
        ok "Root CA exported to: $root_ca_path"
    else
        warn "Could not export Root CA"
    fi
fi

echo ""
echo "============================================================"
ok "Certificate generated successfully!"
echo "============================================================"
echo ""
echo "Files created:"
echo "  Certificate:    $cert_file"
echo "  Private Key:    $key_file"
echo "  CA Chain:       $ca_chain_file"
echo "  Bundle:         $bundle_file"
echo ""
info "Serial Number: $serial_number"
info "Expiration: $expiration"
