#!/bin/bash
# Automatic Certificate Rotation Script
# 
# Überwacht Zertifikate und erneuert sie, wenn sie bald ablaufen
# 
# Installation (Cron):
#   0 2 * * * /path/to/rotate-certs.sh >> /var/log/cert-rotation.log 2>&1

set -e

# Configuration
CERTS_DIR="${CERTS_DIR:-./certs}"
CA_URL="${CA_URL:-http://localhost:9000}"
DAYS_BEFORE_EXPIRY=${DAYS_BEFORE_EXPIRY:-30}
WEBHOOK_URL="${WEBHOOK_URL:-}"  # Optional: für Benachrichtigungen
LOG_FILE="${LOG_FILE:-./cert-rotation.log}"
INSECURE="${INSECURE:---insecure}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper Functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[${timestamp}]${NC} ${GREEN}ℹ${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${BLUE}[${timestamp}]${NC} ${YELLOW}⚠${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${BLUE}[${timestamp}]${NC} ${RED}✖${NC} $message" | tee -a "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${BLUE}[${timestamp}]${NC} ${GREEN}✓${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Berechne Tage bis Ablauf
days_until_expiry() {
    local cert_file=$1
    
    if [ ! -f "$cert_file" ]; then
        echo "-1"
        return
    fi
    
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiry_date" ]; then
        # Fallback für PEM ohne openssl
        local expiry_date=$(step certificate inspect "$cert_file" --format json 2>/dev/null | grep -o '"validTo":"[^"]*' | cut -d'"' -f4)
    fi
    
    if [ -z "$expiry_date" ]; then
        echo "0"
        return
    fi
    
    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -f - +%s <<< "$expiry_date")
    local now_epoch=$(date +%s)
    local days=$(( ($expiry_epoch - $now_epoch) / 86400 ))
    
    echo "$days"
}

# Rotiere ein Zertifikat
rotate_certificate() {
    local cert_file=$1
    local key_file=$2
    local cert_name=$(basename "$cert_file" .crt)
    
    log "INFO" "Erneuere Zertifikat: $cert_name"
    
    # Extract CN/SAN von altem Zertifikat
    local old_cn=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/.*CN=//; s/,.*//')
    local old_sans=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/.*DNS://g' || echo "")
    
    # Backup old certificate
    if [ -f "$cert_file" ]; then
        cp "$cert_file" "$cert_file.bak.$(date +%s)"
        log "INFO" "Backup erstellt: $cert_file.bak.*"
    fi
    
    # Request neues Zertifikat
    local step_args=(
        "ca" "certificate"
        "--ca-url" "$CA_URL"
        $INSECURE
        "--not-after" "2160h"
    )
    
    # SANs hinzufügen
    if [ ! -z "$old_sans" ]; then
        step_args+=("--san" "$old_sans")
    fi
    
    step_args+=("$old_cn" "$cert_file" "$key_file")
    
    if step "${step_args[@]}" &>/dev/null; then
        log "SUCCESS" "Zertifikat erneuert: $cert_name"
        
        # Webhook notification
        if [ ! -z "$WEBHOOK_URL" ]; then
            send_webhook "success" "$cert_name"
        fi
        
        return 0
    else
        log "ERROR" "Fehler beim Erneuern von $cert_name"
        
        # Restore backup
        if [ -f "$cert_file.bak.$(date +%s)" ]; then
            local latest_bak=$(ls -t "$cert_file.bak."* 2>/dev/null | head -1)
            if [ ! -z "$latest_bak" ]; then
                cp "$latest_bak" "$cert_file"
                log "WARN" "Backup wiederhergestellt"
            fi
        fi
        
        # Webhook notification
        if [ ! -z "$WEBHOOK_URL" ]; then
            send_webhook "error" "$cert_name"
        fi
        
        return 1
    fi
}

# Sende Webhook Notification (z.B. zu Slack oder Discord)
send_webhook() {
    local status=$1
    local cert_name=$2
    
    if [ -z "$WEBHOOK_URL" ]; then
        return
    fi
    
    local color="36a64f"  # green
    if [ "$status" = "error" ]; then
        color="ff0000"  # red
    elif [ "$status" = "soon" ]; then
        color="ffaa00"  # orange
    fi
    
    local message="Zertifikat $cert_name: $status"
    
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$message\", \"color\": \"$color\"}" \
        2>/dev/null || true
}

# Main Rotation Logic
run_rotation() {
    log "INFO" "=== Zertifikat Rotation gestartet ==="
    
    if [ ! -d "$CERTS_DIR" ]; then
        log "WARN" "Zertifikatsverzeichnis nicht gefunden: $CERTS_DIR"
        return 1
    fi
    
    local rotated=0
    local failed=0
    local warned=0
    
    # Iteriere über alle Zertifikate
    for cert_file in "$CERTS_DIR"/*.crt; do
        if [ ! -f "$cert_file" ]; then
            continue
        fi
        
        # Ignoriere root_ca und intermediate
        if [[ "$cert_file" == *"root"* ]] || [[ "$cert_file" == *"intermediate"* ]]; then
            continue
        fi
        
        local cert_name=$(basename "$cert_file")
        local key_file="${cert_file%.crt}.key"
        
        if [ ! -f "$key_file" ]; then
            log "WARN" "Kein privater Schlüssel gefunden für: $cert_name"
            continue
        fi
        
        # Berechne Tage bis Ablauf
        local days=$(days_until_expiry "$cert_file")
        
        if [ "$days" -lt 0 ]; then
            log "ERROR" "Zertifikat bereits abgelaufen: $cert_name"
            ((failed++))
            send_webhook "error" "$cert_name"
            continue
        fi
        
        if [ "$days" -lt "$DAYS_BEFORE_EXPIRY" ]; then
            log "WARN" "Zertifikat läuft bald ab: $cert_name ($days Tage)"
            
            if rotate_certificate "$cert_file" "$key_file"; then
                ((rotated++))
            else
                ((failed++))
            fi
        else
            log "INFO" "OK: $cert_name ($days Tage verbleibend)"
            ((warned++))
        fi
    done
    
    log "INFO" "=== Rotation abgeschlossen ==="
    log "INFO" "Erneuert: $rotated | Fehlegschlagen: $failed | OK: $warned"
    
    if [ "$failed" -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# Check Prerequisites
check_prerequisites() {
    local missing=0
    
    if ! command -v step &> /dev/null; then
        log "ERROR" "step CLI nicht gefunden"
        ((missing++))
    fi
    
    if ! command -v openssl &> /dev/null; then
        log "WARN" "openssl nicht gefunden (fallback zu step)"
    fi
    
    if [ $missing -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# Script Entry Point
main() {
    # Create log directory
    mkdir -p "$(dirname "$LOG_FILE")"
    
    log "INFO" "Starte Zertifikat Rotation..."
    log "INFO" "CA URL: $CA_URL"
    log "INFO" "Zertifikatsverzeichnis: $CERTS_DIR"
    log "INFO" "Erneuern wenn < $DAYS_BEFORE_EXPIRY Tage verbleibend"
    
    if ! check_prerequisites; then
        log "ERROR" "Voraussetzungen nicht erfüllt"
        exit 1
    fi
    
    run_rotation
    exit $?
}

# Run if called as script
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
