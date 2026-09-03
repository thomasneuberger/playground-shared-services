# Compare Traefik's Certificate with Vault PKI
<#
.SYNOPSIS
    Diagnoses certificate mismatch between Traefik and Vault PKI

.DESCRIPTION
    Compares the certificate Traefik is serving with the certificates
    in the ./certs folder. Helps identify if Traefik is using the wrong cert.

.PARAMETER TraefikUrl
    Traefik address (default: https://localhost:8443)

.PARAMETER CertsFolder
    Certificates folder (default: ./certs)

.EXAMPLE
    .\diagnose-traefik-cert.ps1
    .\diagnose-traefik-cert.ps1 -TraefikUrl "https://vault.local:8443"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TraefikUrl = "https://localhost:8443",

    [Parameter(Mandatory=$false)]
    [string]$CertsFolder = "./certs"
)

# Color output functions
function Write-Info { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Get-CertInfo {
    param($cert, $label)
    
    Write-Host ""
    Write-Host "Certificate: $label" -ForegroundColor Cyan
    Write-Host "  Subject: $($cert.Subject)"
    Write-Host "  Issuer: $($cert.Issuer)"
    Write-Host "  Thumbprint: $($cert.Thumbprint)"
    Write-Host "  Valid From: $($cert.NotBefore)"
    Write-Host "  Valid Until: $($cert.NotAfter)"
    
    # Get SANs if present
    $sanExt = $cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }
    if ($sanExt) {
        $sanList = $sanExt.Format($false) -split ', '
        Write-Host "  SANs: $($sanList -join ', ')"
    }
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  Traefik Certificate Diagnostics" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

# Step 1: Get certificate from Traefik
Write-Host "[1/4] Retrieving certificate from Traefik..." -ForegroundColor Yellow
$originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

try {
    $uri = [System.Uri]$TraefikUrl
    $hostname = $uri.Host
    $port = if ($uri.Port -eq 443) { 443 } else { $uri.Port }
    
    Write-Info "Connecting to: $hostname`:$port"
    
    # Try to get certificate from Traefik
    try {
        $request = [System.Net.HttpWebRequest]::Create($TraefikUrl)
        $request.GetResponse() | Out-Null
    } catch {
        # Expected to fail, we just want the certificate
    }
    
    $servicePoint = [System.Net.ServicePointManager]::FindServicePoint($uri)
    $traefikCert = $servicePoint.Certificate
    
    if (-not $traefikCert) {
        # Fallback to TCP
        Write-Info "Retrying with direct TCP connection..."
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($hostname, $port)
        
        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(),
            $false,
            { param($sender, $certificate, $chain, $sslPolicyErrors) $true }
        )
        
        try {
            $sslStream.AuthenticateAsClient($hostname)
            $traefikCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
        } finally {
            $sslStream.Dispose()
            $tcpClient.Dispose()
        }
    }
    
    Write-Success "Certificate retrieved from Traefik"
    Get-CertInfo -cert $traefikCert -label "From Traefik"
    
} catch {
    Write-Error "Failed to get certificate from Traefik: $_"
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
    exit 1
} finally {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
}

# Step 2: Find certificate files in certs folder
Write-Host "[2/4] Searching for certificates in $CertsFolder..." -ForegroundColor Yellow

$certFiles = @()
if (Test-Path $CertsFolder) {
    $certFiles = Get-ChildItem -Path $CertsFolder -Filter "*.crt" | Where-Object { $_.Name -notmatch "root_ca" }
    
    if ($certFiles) {
        Write-Success "Found $($certFiles.Count) certificate file(s)"
        foreach ($file in $certFiles) {
            Write-Info "  - $($file.Name)"
        }
    } else {
        Write-Warning "No certificate files found in $CertsFolder"
    }
} else {
    Write-Error "Certificates folder not found: $CertsFolder"
    exit 1
}

$rootMismatchDetected = $false
$chainRelationshipValid = $true
$chainRootFile = $certFiles | Where-Object { $_.Name -like "*-ca-chain.crt" } | Select-Object -First 1

# Step 3: Compare certificates
Write-Host "[3/4] Comparing certificates..." -ForegroundColor Yellow

$matched = $false
$certFiles | ForEach-Object {
    try {
        $fileCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($_.FullName)
        
        Get-CertInfo -cert $fileCert -label "From File: $($_.Name)"
        
        # Compare thumbprints
        if ($fileCert.Thumbprint -eq $traefikCert.Thumbprint) {
            Write-Success "✓ This certificate MATCHES the one from Traefik!"
            $matched = $true
        } else {
            Write-Warning "✗ Thumbprint mismatch"
            Write-Info "  Traefik: $($traefikCert.Thumbprint)"
            Write-Info "  File:    $($fileCert.Thumbprint)"
        }
    } catch {
        Write-Warning "Could not load certificate file $($_.Name): $_"
    }
}

# Step 4: Check root CA
Write-Host "[4/4] Checking Root CA..." -ForegroundColor Yellow

$rootCaPath = Join-Path $CertsFolder "root_ca.crt"
if (Test-Path $rootCaPath) {
    try {
        $rootCa = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($rootCaPath)
        
        Get-CertInfo -cert $rootCa -label "Root CA (from export)"

        # Compare exported root with CA chain cert if present
        if ($chainRootFile) {
            try {
                $chainRootCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($chainRootFile.FullName)
                if ($chainRootCert.Thumbprint -eq $rootCa.Thumbprint) {
                    Write-Success "✓ $($chainRootFile.Name) contains the same certificate as root_ca.crt"
                } else {
                    Write-Info "$($chainRootFile.Name) differs from root_ca.crt (often expected if it's an intermediate CA)"
                    $caChainTest = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                    $caChainTest.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
                    $caChainTest.ChainPolicy.ExtraStore.Add($rootCa) | Out-Null
                    $null = $caChainTest.Build($chainRootCert)

                    $chainAnchorsToRoot = $false
                    if ($caChainTest.ChainElements.Count -gt 0) {
                        $chainAnchorsToRoot = ($caChainTest.ChainElements[$caChainTest.ChainElements.Count - 1].Certificate.Thumbprint -eq $rootCa.Thumbprint)
                    }

                    if ($chainAnchorsToRoot -or $chainRootCert.Issuer -eq $rootCa.Subject) {
                        Write-Success "✓ $($chainRootFile.Name) chains to root_ca.crt"
                    } else {
                        $rootMismatchDetected = $true
                        $chainRelationshipValid = $false
                        Write-Warning "⚠ CA relationship mismatch: $($chainRootFile.Name) does not chain to root_ca.crt"
                        Write-Info "  root_ca.crt thumbprint:       $($rootCa.Thumbprint)"
                        Write-Info "  $($chainRootFile.Name) thumbprint: $($chainRootCert.Thumbprint)"
                        Write-Info "  This may indicate stale or mixed PKI artifacts"
                    }
                }
            } catch {
                Write-Warning "Could not compare root_ca.crt with $($chainRootFile.Name): $_"
            }
        }
        
        # Check if Traefik cert is signed by this root CA
        Write-Info "Checking if Traefik cert is signed by root CA..."

        # Authoritative check: chain must anchor to exported root
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
        $chain.ChainPolicy.ExtraStore.Add($rootCa) | Out-Null
        if ($chainRootFile) {
            try {
                $chainIntermediate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($chainRootFile.FullName)
                $chain.ChainPolicy.ExtraStore.Add($chainIntermediate) | Out-Null
            } catch {
                Write-Warning "Could not load CA chain cert from $($chainRootFile.Name): $_"
            }
        }
        $chainBuildSuccess = $chain.Build($traefikCert)

        $anchorsToRoot = $false
        if ($chain.ChainElements.Count -gt 0) {
            $anchorsToRoot = ($chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Thumbprint -eq $rootCa.Thumbprint)
        }

        if ($chainBuildSuccess -and $anchorsToRoot) {
            Write-Success "✓ Traefik certificate chain anchors to exported Root CA"
        } elseif ($anchorsToRoot) {
            Write-Warning "⚠ Traefik chain has warnings but anchors to exported Root CA"
            foreach ($status in $chain.ChainStatus) {
                Write-Info "  $($status.Status): $($status.StatusInformation)"
            }
        } else {
            Write-Warning "⚠ Traefik certificate does NOT chain to exported Root CA"
            Write-Info "  Traefik cert Issuer: $($traefikCert.Issuer)"
            Write-Info "  Root CA Subject:     $($rootCa.Subject)"
        }
    } catch {
        Write-Error "Could not load Root CA: $_"
    }
} else {
    Write-Warning "Root CA not found: $rootCaPath"
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "Diagnostics Complete" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "Summary:" -ForegroundColor Cyan
if ($matched) {
    Write-Host "  ✓ Traefik is serving a certificate from your certs folder" -ForegroundColor Green
    if ($rootMismatchDetected -or -not $chainRelationshipValid) {
        Write-Host "  ⚠ root_ca.crt appears stale vs CA chain file" -ForegroundColor Yellow
        Write-Host "  ⚠ Re-export Root CA and re-import trust store" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ Everything is properly configured" -ForegroundColor Green
    }
} else {
    Write-Host "  ✗ Traefik is NOT serving any certificate from your certs folder" -ForegroundColor Red
    Write-Host ""
    Write-Host "This means:" -ForegroundColor Yellow
    Write-Host "  - Traefik has an old/outdated certificate" -ForegroundColor Yellow
    Write-Host "  - OR Traefik config is pointing to wrong certificate file" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Solution:" -ForegroundColor Yellow
    Write-Host "  1. Regenerate certificates:" -ForegroundColor White
    Write-Host "     .\scripts\generate-certs-vault.ps1 -Domain `"vault.local`"" -ForegroundColor Cyan
    Write-Host "  2. Check Traefik config at: ./config/traefik/dynamic.yml" -ForegroundColor White
    Write-Host "  3. Restart Traefik:" -ForegroundColor White
    Write-Host "     docker compose restart traefik" -ForegroundColor Cyan
}

Write-Host ""
