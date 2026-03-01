# Bootstrap Vault HTTPS Setup with Traefik - PowerShell Script
# This script helps set up HTTPS for Vault using Traefik reverse proxy

param(
    [Parameter(Mandatory=$false)]
    [string]$VaultAddr = "http://localhost:8201",
    
    [Parameter(Mandatory=$false)]
    [string]$Domain = "vault.local",
    
    [Parameter(Mandatory=$false)]
    [string]$IpSans = "127.0.0.1"
)

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Vault HTTPS Bootstrap Script" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Check if Vault is running
Write-Host "[1/5] Checking Vault status..." -ForegroundColor Yellow
try {
    $vaultStatus = docker compose ps vault --format json | ConvertFrom-Json
    if ($vaultStatus.State -ne "running") {
        Write-Host "❌ Vault is not running. Starting Vault..." -ForegroundColor Red
        docker compose up -d vault vault-pki-init
        Start-Sleep -Seconds 10
    } else {
        Write-Host "✓ Vault is running" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Error checking Vault status: $_" -ForegroundColor Red
    exit 1
}

# Wait for PKI initialization
Write-Host "[2/5] Waiting for PKI initialization..." -ForegroundColor Yellow
$maxWait = 60
$waited = 0
while ($waited -lt $maxWait) {
    try {
        $response = Invoke-WebRequest -Uri "$VaultAddr/v1/sys/health" -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Start-Sleep -Seconds 5
            break
        }
    } catch {
        Write-Host "  Waiting for Vault..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
        $waited += 5
    }
}

if ($waited -ge $maxWait) {
    Write-Host "❌ Vault did not become ready in time" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Vault is ready" -ForegroundColor Green

# Generate certificate for Vault
Write-Host "[3/5] Generating certificate for Vault..." -ForegroundColor Yellow
$certResult = & .\scripts\generate-certs-vault.ps1 -Domain $Domain -IpSans $IpSans -Role "service-cert"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to generate certificate" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Certificate generated" -ForegroundColor Green

# Copy certificate files
$domainName = $Domain.Split(',')[0]
$certFile = "certs\$domainName.crt"
$keyFile = "certs\$domainName.key"

if (-not (Test-Path $certFile) -or -not (Test-Path $keyFile)) {
    Write-Host "❌ Certificate files not found: $certFile, $keyFile" -ForegroundColor Red
    exit 1
}

# Check Traefik configuration
Write-Host "[4/5] Setting up Traefik configuration..." -ForegroundColor Yellow

# Check if Traefik config exists
if (-not (Test-Path "config\traefik\dynamic.yml")) {
    Write-Host "⚠️  Traefik config not found. Creating..." -ForegroundColor Yellow
    
    # Create dynamic.yml if it doesn't exist
    $dynamicConfig = @"
# Traefik Dynamic Configuration - TLS Certificates
http:
  routers:
    vault:
      rule: "Host(``$Domain``) || Host(``localhost``)"
      entryPoints:
        - websecure
      service: vault-service
      tls: {}
  
  services:
    vault-service:
      loadBalancer:
        servers:
          - url: "http://vault:8200"

tls:
  certificates:
    - certFile: /certs/$domainName.crt
      keyFile: /certs/$domainName.key
  stores:
    default:
      defaultCertificate:
        certFile: /certs/$domainName.crt
        keyFile: /certs/$domainName.key
"@
    
    New-Item -ItemType Directory -Path "config\traefik" -Force | Out-Null
    Set-Content -Path "config\traefik\dynamic.yml" -Value $dynamicConfig
}

Write-Host "✓ Traefik configuration ready" -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your docker-compose.yml:" -ForegroundColor Yellow
Write-Host @"
  
  # === TRAEFIK REVERSE PROXY FOR VAULT HTTPS ===
  traefik:
    image: traefik:v2.11
    container_name: shared-traefik
    ports:
      - "8443:443"      # HTTPS for Vault UI
      - "8080:8080"     # Traefik Dashboard (optional)
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.file.filename=/etc/traefik/dynamic.yml"
      - "--entrypoints.websecure.address=:443"
      - "--api.dashboard=true"
      - "--api.insecure=true"
      - "--log.level=INFO"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - ./config/traefik:/etc/traefik:ro
      - ./certs:/certs:ro
    networks:
      - shared-services
    restart: unless-stopped

  # Update Vault service with these labels:
Write-Host "  1. Add traefik service to docker-compose.yml (see above)" -ForegroundColor White
Write-Host "  2. Add labels to vault service (see above)" -ForegroundColor White
Write-Host "  3. Run: docker compose up -d traefik" -ForegroundColor White
Write-Host "  4. Add to hosts file (if using $Domain):" -ForegroundColor White
Write-Host "     127.0.0.1 $Domain" -ForegroundColor Cyan
Write-Host "  5. Access Vault UI:" -ForegroundColor White
Write-Host "     https://localhost:8443" -ForegroundColor Cyan
Write-Host "     https://${Domain}:8443" -ForegroundColor Cyan     - "traefik.http.services.vault.loadbalancer.server.port=8200"
"@ -ForegroundColor White
    
Write-Host ""
Write-Host "Then run: docker compose up -d traefik" -ForegroundColor Yellow

# Trust Root CA
Write-Host "[5/5] Trust Root CA..." -ForegroundColor Yellow
if (Test-Path "certs\root_ca.crt") {
    Write-Host "  Run as Administrator:" -ForegroundColor Cyan
    Write-Host "  certutil -addstore -f `"ROOT`" `"certs\root_ca.crt`"" -ForegroundColor White
} else {
    Write-Host "❌ Root CA not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "   Bootstrap Complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
if ($Mode -eq "nginx") {
    Write-Host "  1. Add vault-nginx service to docker-compose.yml (see above)" -ForegroundColor White
    Write-Host "  2. Run: docker compose up -d vault-nginx" -ForegroundColor White
    Write-Host "  3. Access Vault: https://localhost:8443" -ForegroundColor White
} else {
    Write-Host "  See VAULT_HTTPS_SETUP.md for complete server mode setup" -ForegroundColor White
}
Write-Host ""
Write-Host "Documentation: VAULT_HTTPS_SETUP.md" -ForegroundColor Cyan
