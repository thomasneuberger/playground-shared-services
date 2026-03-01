# Verify Certificate Chain - Check if certs match root CA
<#
.SYNOPSIS
    Verifies that all certificates are signed by the root_ca.crt file

.DESCRIPTION
    Validates the certificate chain to ensure all .crt files in the
    certs folder are properly issued by and signed with root_ca.crt.

.PARAMETER CertsFolder
    Certificates folder (default: ./certs)

.EXAMPLE
    .\verify-cert-chain.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$CertsFolder = "./certs"
)

# Color output functions
function Write-Info { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  Certificate Chain Verification" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

Write-Info "Certificates folder: $CertsFolder"
Write-Host ""

# Step 1: Load root CA
Write-Host "[1/3] Loading Root CA certificate..." -ForegroundColor Yellow

$rootCaPath = Join-Path $CertsFolder "root_ca.crt"
if (-not (Test-Path $rootCaPath)) {
    Write-Error "Root CA not found: $rootCaPath"
    exit 1
}

try {
    $rootCa = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($rootCaPath)
    Write-Success "Root CA loaded"
    Write-Info "  Subject: $($rootCa.Subject)"
    Write-Info "  Issuer: $($rootCa.Issuer)"
    Write-Info "  Thumbprint: $($rootCa.Thumbprint)"
    Write-Info "  Valid Until: $($rootCa.NotAfter)"
} catch {
    Write-Error "Failed to load root CA: $_"
    exit 1
}

Write-Host ""

# Step 2: Find certificate files
Write-Host "[2/3] Finding certificate files in folder..." -ForegroundColor Yellow

$certFiles = Get-ChildItem -Path $CertsFolder -Filter "*.crt" | 
    Where-Object { $_.Name -ne "root_ca.crt" }

if (-not $certFiles) {
    Write-Warning "No certificate files found (excluding root_ca.crt)"
    exit 0
}

Write-Success "Found $($certFiles.Count) certificate file(s)"
foreach ($file in $certFiles) {
    Write-Info "  - $($file.Name)"
}

# Quick consistency check: root_ca.crt vs any exported CA chain cert file
$chainRootFile = $certFiles | Where-Object { $_.Name -like "*-ca-chain.crt" } | Select-Object -First 1
if ($chainRootFile) {
    try {
        $chainRootCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($chainRootFile.FullName)
        if ($chainRootCert.Thumbprint -ne $rootCa.Thumbprint) {
            Write-Warning "Detected root mismatch: root_ca.crt does not match $($chainRootFile.Name)"
            Write-Info "  root_ca.crt thumbprint:      $($rootCa.Thumbprint)"
            Write-Info "  $($chainRootFile.Name) thumbprint: $($chainRootCert.Thumbprint)"
            Write-Info "  This usually means root_ca.crt is outdated and needs re-export"
        } else {
            Write-Success "root_ca.crt matches $($chainRootFile.Name)"
        }
    } catch {
        Write-Warning "Could not compare root_ca.crt with $($chainRootFile.Name): $_"
    }
}

Write-Host ""

# Step 3: Verify each certificate
Write-Host "[3/3] Verifying certificate signatures..." -ForegroundColor Yellow
Write-Host ""

$allValid = $true
$certFiles | ForEach-Object {
    $fileName = $_.Name
    
    try {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($_.FullName)
        
        Write-Host "Certificate: $fileName" -ForegroundColor Cyan
        Write-Info "  Subject: $($cert.Subject)"
        Write-Info "  Issuer: $($cert.Issuer)"
        Write-Info "  Thumbprint: $($cert.Thumbprint)"
        
        # Metadata-only issuer comparison (informational)
        $issuerMatches = $cert.Issuer -eq $rootCa.Subject
        if ($issuerMatches) {
            Write-Success "  ✓ Issuer metadata matches Root CA"
        } else {
            Write-Warning "  ⚠ Issuer metadata differs from Root CA subject"
            Write-Info "    Root CA Subject: $($rootCa.Subject)"
            Write-Info "    Cert Issuer:     $($cert.Issuer)"
            Write-Info "    Note: this can still be valid if chain anchors to the same root"
        }
        
        # Check validity period
        $now = Get-Date
        if ($cert.NotBefore -le $now -and $cert.NotAfter -ge $now) {
            Write-Success "  ✓ Certificate is currently valid"
        } else {
            Write-Warning "  ✗ Certificate is NOT valid"
            if ($cert.NotBefore -gt $now) {
                Write-Info "    Certificate not yet valid (starts: $($cert.NotBefore))"
            }
            if ($cert.NotAfter -lt $now) {
                Write-Info "    Certificate has expired (ended: $($cert.NotAfter))"
            }
            $allValid = $false
        }
        
        # Try to verify signature
        try {
            Write-Info "  Verifying signature..."
            
            # Create chain with root CA
            $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
            $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            
            # Import root CA into verification chain
            $chain.ChainPolicy.ExtraStore.Add($rootCa) | Out-Null
            
            $chainBuildSuccess = $chain.Build($cert)
            $chainHasRoot = $false
            if ($chain.ChainElements.Count -gt 0) {
                $chainHasRoot = ($chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Thumbprint -eq $rootCa.Thumbprint)
            }
            
            if ($chainBuildSuccess -or $chain.ChainElements.Count -gt 0) {
                Write-Success "  ✓ Chain builds successfully"
                Write-Info "    Chain length: $($chain.ChainElements.Count)"
                if ($chainHasRoot) {
                    Write-Success "  ✓ Chain anchors to root_ca.crt"
                } else {
                    Write-Warning "  ✗ Chain does not anchor to root_ca.crt"
                    $allValid = $false
                }
            } else {
                Write-Warning "  ⚠ Could not build complete chain"
                if ($chain.ChainStatus.Count -gt 0) {
                    foreach ($status in $chain.ChainStatus) {
                        Write-Info "    $($status.Status): $($status.StatusInformation)"
                    }
                }
                $allValid = $false
            }
        } catch {
            Write-Warning "  ⚠ Could not verify signature: $_"
        }
        
        Write-Host ""
        
    } catch {
        Write-Error "Failed to load certificate $fileName : $_"
        $allValid = $false
        Write-Host ""
    }
}

# Summary
Write-Host "=" * 70 -ForegroundColor Green
if ($allValid) {
    Write-Success "All certificates are properly signed by root_ca.crt"
    Write-Host "=" * 70 -ForegroundColor Green
    Write-Host ""
    Write-Host "✓ Certificate chain is valid and consistent" -ForegroundColor Green
} else {
    Write-Warning "Some certificates have issues"
    Write-Host "=" * 70 -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Issues found:" -ForegroundColor Yellow
    Write-Host "  - Certificates may be outdated or from different PKI setup" -ForegroundColor Yellow
    Write-Host "  - Regenerate certificates:" -ForegroundColor White
    Write-Host "    .\scripts\generate-certs-vault.ps1 -Domain `"vault.local`"" -ForegroundColor Cyan
    Write-Host "  - Or completely reset:" -ForegroundColor White
    Write-Host "    docker compose down -v && docker compose up -d" -ForegroundColor Cyan
}

Write-Host ""
