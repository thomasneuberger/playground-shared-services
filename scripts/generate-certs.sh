#!/bin/bash
# Generate certificates using Step CA
# 
# Usage:
#   ./generate-certs.sh                    # Interactive
#   ./generate-certs.sh myapp.local        # Specific domain
#   ./generate-certs.sh myapp.local api    # Domain + client cert

set -e

CA_URL="${CA_URL:-http://localhost:9000}"
CERTS_DIR="${CERTS_DIR:-./certs}"
INSECURE="${INSECURE:---insecure}"  # Use --insecure only for self-signed

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
  echo -e "${GREEN}ℹ${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✖${NC} $1"
}

# Create certs directory
mkdir -p "$CERTS_DIR"

# Step CA Health Check
log_info "Überprüfe Step CA Erreichbarkeit..."
if ! step ca health --ca-url "$CA_URL" $INSECURE &>/dev/null; then
  log_error "Step CA nicht erreichbar unter $CA_URL"
  exit 1
fi
log_info "Step CA ist erreichbar ✓"

# Determine what to generate
if [ $# -eq 0 ]; then
  # Interactive mode
  echo ""
  echo "=== Step CA Zertifikat Generator ==="
  echo ""
  echo "Was möchtest du generieren?"
  echo "1) Server-Zertifikat für eine Domain"
  echo "2) Client-Zertifikat"
  echo "3) Beides (Server + Client)"
  echo "4) Root CA exportieren"
  echo ""
  read -p "Wähle (1-4): " choice
  
  case $choice in
    1)
      read -p "Domain-Name (z.B. myapp.local): " domain
      read -p "Alternative SANs (optional, kommagetrennt): " sans
      gen_server_cert "$domain" "$sans"
      ;;
    2)
      read -p "Client Name (z.B. client@example.com): " client_name
      gen_client_cert "$client_name"
      ;;
    3)
      read -p "Domain-Name (z.B. myapp.local): " domain
      read -p "Alternative SANs (optional, kommagetrennt): " sans
      read -p "Client Name (z.B. client@example.com): " client_name
      gen_server_cert "$domain" "$sans"
      gen_client_cert "$client_name"
      ;;
    4)
      export_root_ca
      ;;
    *)
      log_error "Ungültige Auswahl"
      exit 1
      ;;
  esac
else
  # Command-line mode
  case $1 in
    --help|-h)
      show_help
      ;;
    --root-ca)
      export_root_ca
      ;;
    *)
      domain=$1
      client=$2
      
      log_info "Generiere Server-Zertifikat für: $domain"
      gen_server_cert "$domain" ""
      
      if [ ! -z "$client" ]; then
        log_info "Generiere Client-Zertifikat für: $client"
        gen_client_cert "$client"
      fi
      ;;
  esac
fi

# Completion
echo ""
log_info "Zertifikate erfolgreich generiert!"
echo ""
ls -lh "$CERTS_DIR"
echo ""

# Helper Functions

gen_server_cert() {
  local domain=$1
  local sans=$2
  
  if [ -z "$domain" ]; then
    log_error "Domain erforderlich"
    return 1
  fi
  
  # Build SAN parameter
  local san_param=""
  if [ ! -z "$sans" ]; then
    san_param="--san $sans"
  fi
  
  log_info "Generiere Server-Zertifikat für '$domain'..."
  
  step ca certificate \
    --ca-url "$CA_URL" \
    --san "$domain" \
    $san_param \
    --insecure \
    --not-after 2160h \
    "$domain" \
    "$CERTS_DIR/${domain}.crt" \
    "$CERTS_DIR/${domain}.key"
  
  log_info "✓ Zertifikat: $CERTS_DIR/${domain}.crt"
  log_info "✓ Privater Schlüssel: $CERTS_DIR/${domain}.key"
  
  # Show certificate details
  echo ""
  log_info "Zertifikat-Details:"
  step certificate inspect "$CERTS_DIR/${domain}.crt" --format json | \
    jq '.subject, .validFrom, .validTo, .sanList' || true
}

gen_client_cert() {
  local client=$1
  
  if [ -z "$client" ]; then
    log_error "Client Name erforderlich"
    return 1
  fi
  
  # Sanitize filename
  local filename=$(echo "$client" | tr '@' '_' | tr ' ' '_')
  
  log_info "Generiere Client-Zertifikat für '$client'..."
  
  step ca certificate \
    --ca-url "$CA_URL" \
    --profile leaf \
    --insecure \
    --not-after 2160h \
    "$client" \
    "$CERTS_DIR/${filename}.crt" \
    "$CERTS_DIR/${filename}.key"
  
  log_info "✓ Zertifikat: $CERTS_DIR/${filename}.crt"
  log_info "✓ Privater Schlüssel: $CERTS_DIR/${filename}.key"
  
  echo ""
  log_info "Zertifikat-Details:"
  step certificate inspect "$CERTS_DIR/${filename}.crt" --format json | \
    jq '.subject, .validFrom, .validTo' || true
}

export_root_ca() {
  log_info "Exportiere Root CA..."
  
  docker cp shared-step-ca:/home/step/certs/root_ca.crt \
    "$CERTS_DIR/root_ca.crt" 2>/dev/null || {
    log_warn "Docker Copy fehlgeschlagen. Versuche SSH..."
    # Fallback: über Step CA API holen (wenn verfügbar)
    curl -s -k "$CA_URL/roots.pem" > "$CERTS_DIR/root_ca.crt"
  }
  
  if [ -f "$CERTS_DIR/root_ca.crt" ]; then
    log_info "✓ Root CA: $CERTS_DIR/root_ca.crt"
    
    log_warn ""
    log_warn "WICHTIG: Root CA ins System Trust Store laden:"
    
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
      log_warn "Windows:"
      log_warn "  Import-Certificate -FilePath '.\\certs\\root_ca.crt' \\"
      log_warn "    -CertStoreLocation 'Cert:\\LocalMachine\\Root'"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      log_warn "macOS:"
      log_warn "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./certs/root_ca.crt"
    else
      log_warn "Linux (Ubuntu/Debian):"
      log_warn "  sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/"
      log_warn "  sudo update-ca-certificates"
    fi
  else
    log_error "Root CA konnte nicht exportiert werden"
    return 1
  fi
}

show_help() {
  cat << EOF
Step CA Zertifikat Generator

VERWENDUNG:
  $0                                 # Interaktiver Modus
  $0 domain.local                   # Server-Zertifikat
  $0 domain.local client-name       # Server + Client
  $0 --root-ca                      # Root CA exportieren
  $0 --help                         # Diese Hilfe anzeigen

ENVIRONMENT:
  CA_URL           Step CA Adresse (default: http://localhost:9000)
  CERTS_DIR        Zertifikatsverzeichnis (default: ./certs)
  INSECURE         --insecure Flag für selbstsignierte CA (default: true)

BEISPIELE:
  # Server-Zertifikat für myapp.local
  $0 myapp.local

  # Server + Client
  $0 myapp.local client@example.com

  # Mit Custom Verzeichnis
  CERTS_DIR=/etc/myapp/certs $0 api.local

EOF
}

# Run if called as script (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [$# -eq 0] && show_help || true
fi
