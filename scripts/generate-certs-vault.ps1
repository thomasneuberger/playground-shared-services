# Generate certificates using Vault PKI Engine - Windows Edition
<#
.SYNOPSIS
    Generates SSL/TLS certificates using HashiCorp Vault PKI Engine

.DESCRIPTION
    This script generates server and/or client certificates using Vault PKI Engine.
    It supports server certificates, client certificates, and combined service certificates.

.PARAMETER Domain
    The domain name for the certificate (e.g., localhost, myapp.local)

.PARAMETER CommonName
    Common Name for client certificates (e.g., user@example.com, service-account)

.PARAMETER IpSans
    Comma-separated list of IP addresses to include as SANs (e.g., "127.0.0.1,192.168.1.10")

.PARAMETER Role
    Vault PKI role to use: server-cert, client-cert, or service-cert (default: server-cert)

.PARAMETER VaultAddr
    Vault address (default: http://localhost:8201)

.PARAMETER VaultToken
    Vault token for authentication (default: from parameter > $env:VAULT_TOKEN > .env file > myroot123)

.PARAMETER OutputDir
    Output directory for certificates (default: ./certs)

.PARAMETER ExportRootCA
    Export the root CA certificate only

.EXAMPLE
    .\generate-certs-vault.ps1 -Domain "localhost"
    Generates a server certificate for localhost

.EXAMPLE
    .\generate-certs-vault.ps1 -Domain "myapp.local" -IpSans "192.168.1.10"
    Generates a server certificate with IP SAN

.EXAMPLE
    .\generate-certs-vault.ps1 -CommonName "client@example.com" -Role "client-cert"
    Generates a client certificate

.EXAMPLE
    .\generate-certs-vault.ps1 -ExportRootCA
    Exports the root CA certificate
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [string]$CommonName,

    [Parameter(Mandatory=$false)]
    [string]$IpSans,

    [Parameter(Mandatory=$false)]
    [ValidateSet("server-cert", "client-cert", "service-cert")]
    [string]$Role = "server-cert",

    [Parameter(Mandatory=$false)]
    [string]$VaultAddr = "http://localhost:8201",

    [Parameter(Mandatory=$false)]
    [string]$VaultToken,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "./certs",

    [Parameter(Mandatory=$false)]
    [switch]$ExportRootCA
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
Write-Host "  Vault PKI Certificate Generator (Windows)" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Set Vault environment variables
$env:VAULT_ADDR = $VaultAddr

# Determine Vault token (priority: parameter > env var > .env file > default)
if ($VaultToken) {
    $env:VAULT_TOKEN = $VaultToken
    Write-Info "Using provided Vault token"
} elseif ($env:VAULT_TOKEN) {
    Write-Info "Using Vault token from environment variable"
} else {
    # Try to read from .env file
    $tokenFromFile = Get-VaultTokenFromEnv
    if ($tokenFromFile) {
        $env:VAULT_TOKEN = $tokenFromFile
        Write-Info "Using Vault token from .env file"
    } else {
        $env:VAULT_TOKEN = "myroot123"
        Write-Warning "No VAULT_TOKEN found, using default: myroot123"
    }
}

# Check if vault CLI is available
$vaultCmd = Get-Command vault -ErrorAction SilentlyContinue
if (-not $vaultCmd) {
    Write-Error "Vault CLI not found. Please install it from: https://www.vaultproject.io/downloads"
    Write-Info "Or run: choco install vault"
    exit 1
}

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Write-Info "Created directory: $OutputDir"
}

# Export Root CA only
if ($ExportRootCA) {
    Write-Info "Exporting Root CA certificate..."
    
    try {
        $rootCaJson = vault read -format=json pki/cert/ca 2>&1 | Out-String
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to read root CA from Vault: $rootCaJson"
            exit 1
        }
        
        $rootCaObject = $rootCaJson | ConvertFrom-Json
        $rootCaCert = $rootCaObject.data.certificate
        $rootCaPath = Join-Path $OutputDir "root_ca.crt"
        
        $rootCaCert | Out-File -FilePath $rootCaPath -Encoding UTF8 -NoNewline
        
        Write-Success "Root CA exported to: $rootCaPath"
        Write-Host ""
        Write-Info "To trust this CA on Windows:"
        Write-Host "  certutil -addstore -f `"ROOT`" `"$rootCaPath`"" -ForegroundColor Yellow
        Write-Host ""
    } catch {
        Write-Error "Failed to export root CA: $_"
        exit 1
    }
    
    exit 0
}

# Determine what to generate
$certName = ""
$certPath = ""

if ($Role -eq "client-cert") {
    if (-not $CommonName) {
        Write-Error "CommonName is required for client certificates"
        Write-Info "Usage: .\generate-certs-vault.ps1 -CommonName `"user@example.com`" -Role client-cert"
        exit 1
    }
    $certName = $CommonName
    $certPath = Join-Path $OutputDir ($CommonName -replace '@', '_' -replace '\.', '_')
} else {
    if (-not $Domain) {
        Write-Error "Domain is required for server/service certificates"
        Write-Info "Usage: .\generate-certs-vault.ps1 -Domain `"localhost`""
        exit 1
    }
    $certName = $Domain
    $certPath = Join-Path $OutputDir $Domain
}

Write-Info "Certificate Type: $Role"
Write-Info "Certificate Name: $certName"
Write-Host ""

# Build Vault write command
$vaultArgs = @("write", "-format=json", "pki_int/issue/$Role")

if ($Role -eq "client-cert") {
    $vaultArgs += "common_name=$CommonName"
} else {
    $vaultArgs += "common_name=$Domain"
    $vaultArgs += "alt_names=$Domain"
}

if ($IpSans) {
    $vaultArgs += "ip_sans=$IpSans"
}

$vaultArgs += "ttl=8760h"

# Generate certificate
Write-Info "Generating certificate from Vault PKI..."
try {
    $result = & vault $vaultArgs 2>&1 | Out-String
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to generate certificate:"
        Write-Host $result -ForegroundColor Red
        exit 1
    }
    
    $json = $result | ConvertFrom-Json
    $certData = $json.data
    
    # Save certificate with CA chain
    $certFile = "$certPath.crt"
    $certContent = @($certData.certificate) + $certData.ca_chain
    $certContent -join "`n" | Out-File -FilePath $certFile -Encoding ASCII
    Write-Success "Certificate with CA chain saved: $certFile"
    
    # Save private key
    $keyFile = "$certPath.key"
    $certData.private_key | Out-File -FilePath $keyFile -Encoding ASCII
    Write-Success "Private key saved: $keyFile"
    
    # Save CA chain
    $caChainFile = "$certPath-ca-chain.crt"
    $certData.ca_chain -join "`n" | Out-File -FilePath $caChainFile -Encoding ASCII
    Write-Success "CA chain saved: $caChainFile"
    
    # Save certificate bundle (cert + CA chain)
    $bundleFile = "$certPath-bundle.crt"
    (@($certData.certificate) + $certData.ca_chain) -join "`n" | Out-File -FilePath $bundleFile -Encoding ASCII
    Write-Success "Certificate bundle saved: $bundleFile"
    
    # Display certificate info
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Green
    Write-Success "Certificate generated successfully!"
    Write-Host "=" * 60 -ForegroundColor Green
    Write-Host ""
    Write-Host "Files created:" -ForegroundColor Cyan
    Write-Host "  Certificate:    $certFile" -ForegroundColor White
    Write-Host "  Private Key:    $keyFile" -ForegroundColor White
    Write-Host "  CA Chain:       $caChainFile" -ForegroundColor White
    Write-Host "  Bundle:         $bundleFile" -ForegroundColor White
    Write-Host ""
    
    Write-Info "Serial Number: $($certData.serial_number)"
    Write-Info "Expiration: $($certData.expiration)"
    Write-Host ""
    
    # Export Root CA if not already exists
    $rootCaPath = Join-Path $OutputDir "root_ca.crt"
    if (-not (Test-Path $rootCaPath)) {
        Write-Info "Exporting Root CA certificate..."
        try {
            $rootCaJson = vault read -format=json pki/cert/ca 2>&1 | Out-String
            $rootCaObject = $rootCaJson | ConvertFrom-Json
            $rootCaCert = $rootCaObject.data.certificate
            $rootCaCert | Out-File -FilePath $rootCaPath -Encoding UTF8 -NoNewline
            Write-Success "Root CA exported to: $rootCaPath"
        } catch {
            Write-Warning "Could not export Root CA: $_"
        }
    }
    
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Trust the Root CA:" -ForegroundColor White
    Write-Host "     certutil -addstore -f `"ROOT`" `"$rootCaPath`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Use in your application:" -ForegroundColor White
    Write-Host "     Certificate: $certFile" -ForegroundColor Cyan
    Write-Host "     Private Key: $keyFile" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Error "Failed to generate certificate: $_"
    exit 1
}
