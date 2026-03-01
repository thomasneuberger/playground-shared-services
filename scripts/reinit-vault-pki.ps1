# Reinitialize Vault PKI - Windows Edition
<#
.SYNOPSIS
    Completely reinitializes Vault PKI engines and creates certificate roles

.DESCRIPTION
    This script disables and recreates the Vault PKI and Intermediate PKI engines,
    sets up a Root CA and Intermediate CA properly, and creates certificate roles.
    Use this if your initial PKI setup failed.

.PARAMETER VaultAddr
    Vault address (default: http://localhost:8201)

.PARAMETER VaultToken
    Vault token for authentication (default: from .env file or myroot123)

.EXAMPLE
    .\reinit-vault-pki.ps1
    .\reinit-vault-pki.ps1 -VaultAddr "http://nbgnas2.local:8201"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$VaultAddr = "http://localhost:8201",

    [Parameter(Mandatory=$false)]
    [string]$VaultToken
)

# Color output functions
function Write-Info { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Function to read token from .env file
function Get-VaultTokenFromEnv {
    $envFile = ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile
        foreach ($line in $envContent) {
            if ($line -match '^VAULT_TOKEN=(.+)$') {
                return $matches[1].Trim()
            }
        }
    }
    return $null
}

# Banner
Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "  Vault PKI Reinitialization" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Set Vault environment
$env:VAULT_ADDR = $VaultAddr

# Determine token
if ($VaultToken) {
    $env:VAULT_TOKEN = $VaultToken
    Write-Info "Using provided Vault token"
} elseif ($env:VAULT_TOKEN) {
    Write-Info "Using Vault token from environment variable"
} else {
    $tokenFromFile = Get-VaultTokenFromEnv
    if ($tokenFromFile) {
        $env:VAULT_TOKEN = $tokenFromFile
        Write-Info "Using Vault token from .env file"
    } else {
        $env:VAULT_TOKEN = "myroot123"
        Write-Warning "Using default token: myroot123"
    }
}

Write-Info "Vault Address: $VaultAddr"
Write-Host ""

# Check vault CLI
$vaultCmd = Get-Command vault -ErrorAction SilentlyContinue
if (-not $vaultCmd) {
    Write-Error "Vault CLI not found"
    exit 1
}

Write-Host "Proceeding with PKI reinitialization..." -ForegroundColor Yellow
$confirmation = Read-Host "This will reset your PKI setup. Continue? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Info "Cancelled"
    exit 0
}

Write-Host ""

# Step 1: Disable existing PKI engines
Write-Info "Step 1: Disabling existing PKI engines..."
try {
    vault secrets disable pki 2>&1 | Out-Null
    Write-Success "  ✓ Root PKI disabled"
} catch {
    Write-Info "  - Root PKI was not mounted"
}

try {
    vault secrets disable pki_int 2>&1 | Out-Null
    Write-Success "  ✓ Intermediate PKI disabled"
} catch {
    Write-Info "  - Intermediate PKI was not mounted"
}

Start-Sleep -Seconds 2

# Step 2: Enable PKI engines
Write-Info "Step 2: Enabling PKI engines..."
try {
    vault secrets enable -path=pki pki
    Write-Success "  ✓ Root PKI enabled"
} catch {
    Write-Error "  Failed to enable root PKI: $_"
    exit 1
}

try {
    vault secrets enable -path=pki_int pki
    Write-Success "  ✓ Intermediate PKI enabled"
} catch {
    Write-Error "  Failed to enable intermediate PKI: $_"
    exit 1
}

# Step 3: Configure PKI engines
Write-Info "Step 3: Configuring PKI engines..."
try {
    vault secrets tune -max-lease-ttl=87600h pki | Out-Null
    Write-Info "  - Set root PKI max TTL to 87600h"
} catch {
    Write-Warning "  Could not tune root PKI: $_"
}

try {
    vault secrets tune -max-lease-ttl=43800h pki_int | Out-Null
    Write-Info "  - Set intermediate PKI max TTL to 43800h"
} catch {
    Write-Warning "  Could not tune intermediate PKI: $_"
}

Write-Success "  ✓ PKI engines configured"

# Step 4: Generate Root CA
Write-Info "Step 4: Generating Root CA certificate..."
try {
    $output = vault write -format=json pki/root/generate/internal `
        common_name="Shared Services Root CA" `
        organization="Shared Services" `
        ttl=87600h `
        key_bits=4096 `
        exclude_cn_from_sans=true 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Failed to generate root CA"
        Write-Host $output -ForegroundColor Red
        exit 1
    }
    
    Write-Success "  ✓ Root CA generated successfully"
} catch {
    Write-Error "  Error generating root CA: $_"
    exit 1
}

# Step 5: Configure Root CA URLs
Write-Info "Step 5: Configuring Root CA URLs..."
try {
    vault write pki/config/urls `
        issuing_certificates="http://vault:8200/v1/pki/ca" `
        crl_distribution_points="http://vault:8200/v1/pki/crl" | Out-Null
    Write-Success "  ✓ Root CA URLs configured"
} catch {
    Write-Error "  Failed to configure root CA URLs: $_"
    exit 1
}

# Step 6: Generate Intermediate CSR
Write-Info "Step 6: Generating Intermediate CA CSR..."
try {
    $output = vault write -format=json pki_int/intermediate/generate/internal `
        common_name="Shared Services Intermediate CA" `
        organization="Shared Services" `
        key_bits=4096 `
        exclude_cn_from_sans=true 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Failed to generate intermediate CSR"
        Write-Host $output -ForegroundColor Red
        exit 1
    }
    
    $json = $output | ConvertFrom-Json
    $csr = $json.data.csr
    
    Write-Success "  ✓ Intermediate CSR generated"
} catch {
    Write-Error "  Error generating intermediate CSR: $_"
    exit 1
}

# Step 7: Sign Intermediate Certificate
Write-Info "Step 7: Signing Intermediate certificate with Root CA..."
try {
    $output = vault write -format=json pki/root/sign-intermediate `
        csr=$csr `
        format=pem_bundle `
        ttl=43800h 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Failed to sign intermediate certificate"
        Write-Host $output -ForegroundColor Red
        exit 1
    }
    
    $json = $output | ConvertFrom-Json
    $cert = $json.data.certificate
    
    Write-Success "  ✓ Intermediate certificate signed"
} catch {
    Write-Error "  Error signing intermediate certificate: $_"
    exit 1
}

# Step 8: Install Signed Certificate
Write-Info "Step 8: Installing signed Intermediate certificate..."
try {
    $output = vault write pki_int/intermediate/set-signed certificate=$cert 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Failed to install intermediate certificate"
        Write-Host $output -ForegroundColor Red
        exit 1
    }
    
    Write-Success "  ✓ Intermediate certificate installed"
} catch {
    Write-Error "  Error installing intermediate certificate: $_"
    exit 1
}

# Step 9: Configure Intermediate CA URLs
Write-Info "Step 9: Configuring Intermediate CA URLs..."
try {
    vault write pki_int/config/urls `
        issuing_certificates="http://vault:8200/v1/pki_int/ca" `
        crl_distribution_points="http://vault:8200/v1/pki_int/crl" | Out-Null
    Write-Success "  ✓ Intermediate CA URLs configured"
} catch {
    Write-Error "  Failed to configure intermediate CA URLs: $_"
    exit 1
}

# Step 10: Create Certificate Roles
Write-Info "Step 10: Creating certificate roles..."

try {
    # Server certificate role
    vault write pki_int/roles/server-cert `
        allowed_domains="localhost,*.local,*.svc,*.svc.cluster.local" `
        allow_subdomains=true `
        allow_localhost=true `
        allow_bare_domains=true `
        allow_ip_sans=true `
        server_flag=true `
        client_flag=false `
        max_ttl=8760h `
        ttl=8760h `
        key_bits=2048 | Out-Null
    Write-Success "  ✓ server-cert role created"
} catch {
    Write-Error "  Error creating server-cert role: $_"
    exit 1
}

try {
    # Client certificate role
    vault write pki_int/roles/client-cert `
        allow_any_name=true `
        enforce_hostnames=false `
        server_flag=false `
        client_flag=true `
        max_ttl=8760h `
        ttl=8760h `
        key_bits=2048 | Out-Null
    Write-Success "  ✓ client-cert role created"
} catch {
    Write-Error "  Error creating client-cert role: $_"
    exit 1
}

try {
    # Service certificate role
    vault write pki_int/roles/service-cert `
        allowed_domains="localhost,*.local,*.svc,*.svc.cluster.local" `
        allow_subdomains=true `
        allow_localhost=true `
        allow_bare_domains=true `
        allow_ip_sans=true `
        server_flag=true `
        client_flag=true `
        max_ttl=8760h `
        ttl=8760h `
        key_bits=2048 | Out-Null
    Write-Success "  ✓ service-cert role created"
} catch {
    Write-Error "  Error creating service-cert role: $_"
    exit 1
}

# Step 11: Export Root CA
Write-Info "Step 11: Exporting Root CA certificate..."
try {
    $output = vault read -field=certificate pki/cert/ca 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "  Failed to export root CA"
        Write-Host $output -ForegroundColor Red
        exit 1
    }
    
    $certDir = "./certs"
    if (-not (Test-Path $certDir)) {
        New-Item -ItemType Directory -Path $certDir | Out-Null
    }
    
    $output | Out-File -FilePath "$certDir/root_ca.crt" -Encoding ASCII
    Write-Success "  ✓ Root CA exported to $certDir/root_ca.crt"
} catch {
    Write-Error "  Error exporting root CA: $_"
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Green
Write-Success "Vault PKI has been reinitialized successfully!"
Write-Host "=" * 60 -ForegroundColor Green
Write-Host ""

Write-Host "Available certificate roles:" -ForegroundColor Cyan
Write-Host "  • server-cert  - For HTTPS/TLS servers" -ForegroundColor White
Write-Host "  • client-cert  - For mTLS clients" -ForegroundColor White
Write-Host "  • service-cert - For services using both server and client auth" -ForegroundColor White
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Trust the Root CA (Windows):" -ForegroundColor White
Write-Host "     certutil -addstore -f `"ROOT`" `"./certs/root_ca.crt`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "  2. Generate certificates:" -ForegroundColor White
Write-Host "     .\scripts\generate-certs-vault.ps1 -Domain `"nbgnas2.local`"" -ForegroundColor Cyan
Write-Host ""
