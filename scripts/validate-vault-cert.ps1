# Validate Vault Certificate - Comprehensive Diagnostics
<#
.SYNOPSIS
    Validates the Vault certificate and diagnoses HTTPS issues

.DESCRIPTION
    Checks certificate validity, chain, SANs, expiration, and trust status.
    Helps diagnose why browsers reject the certificate.

.PARAMETER VaultAddr
    Vault address (default: https://localhost:8443)

.PARAMETER Domain
    Domain to validate (default: vault.local)

.EXAMPLE
    .\validate-vault-cert.ps1
    .\validate-vault-cert.ps1 -VaultAddr "https://nbgnas2.local:8443" -Domain "nbgnas2.local"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$VaultAddr = "https://localhost:8443",

    [Parameter(Mandatory=$false)]
    [string]$Domain = "vault.local"
)

# Color output functions
function Write-Info { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  Vault Certificate Validation" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

Write-Info "Vault Address: $VaultAddr"
Write-Info "Domain to validate: $Domain"
Write-Host ""

# Step 1: Retrieve certificate from server
Write-Host "[1/7] Retrieving certificate from server..." -ForegroundColor Yellow
try {
    $uri = [System.Uri]$VaultAddr
    $hostname = $uri.Host
    $port = if ($uri.Port -eq 443) { 443 } else { $uri.Port }
    
    Write-Info "Connecting to: $hostname`:$port"
    
    # Disable certificate validation temporarily just to retrieve the cert
    $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    
    try {
        $request = [System.Net.HttpWebRequest]::Create($VaultAddr)
        $request.GetResponse() | Out-Null
    } catch {
        # We expect this to fail, we just want the certificate
    }
    
    # Get the certificate from the service point
    $servicePoint = [System.Net.ServicePointManager]::FindServicePoint($uri)
    $cert = $servicePoint.Certificate
    
    if (-not $cert) {
        # Fallback: try direct TCP connection
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
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
        } finally {
            $sslStream.Dispose()
            $tcpClient.Dispose()
        }
    }
    
    # Restore original callback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
    
    Write-Success "Certificate retrieved"
} catch {
    Write-Error "Failed to retrieve certificate: $_"
    exit 1
}

Write-Host ""

# Step 2: Check certificate validity dates
Write-Host "[2/7] Checking certificate validity dates..." -ForegroundColor Yellow
$now = Get-Date
$notBefore = [datetime]$cert.NotBefore
$notAfter = [datetime]$cert.NotAfter

Write-Info "Valid From: $($notBefore.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Info "Valid Until: $($notAfter.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Info "Days until expiry: $(($notAfter - $now).Days)"

if ($now -lt $notBefore) {
    Write-Error "Certificate is not yet valid (starts in future)"
} elseif ($now -gt $notAfter) {
    Write-Error "Certificate is EXPIRED"
} else {
    Write-Success "Certificate is valid (not expired)"
}

Write-Host ""

# Step 3: Check Subject and Issuer
Write-Host "[3/7] Checking certificate subject and issuer..." -ForegroundColor Yellow
Write-Info "Subject: $($cert.Subject)"
Write-Info "Issuer: $($cert.Issuer)"

# Extract CN from subject
$subjectCN = $cert.Subject -split ',' | Where-Object { $_.Trim() -match '^CN=' } | ForEach-Object { $_.Split('=')[1] }
Write-Info "Common Name (CN): $subjectCN"

Write-Success "Subject and issuer retrieved"

Write-Host ""

# Step 4: Check Subject Alternative Names (SANs)
Write-Host "[4/7] Checking Subject Alternative Names (SANs)..." -ForegroundColor Yellow
$sanExtension = $cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }

if ($sanExtension) {
    $sanList = @()
    $sanData = $sanExtension.Format($false)
    
    foreach ($san in $sanData -split ', ') {
        Write-Info "  SAN: $san"
        $sanList += $san
    }
    
    # Check if domain is in SANs
    if ($sanList -match [regex]::Escape($Domain)) {
        Write-Success "✓ Domain '$Domain' found in SANs"
    } else {
        Write-Warning "⚠ Domain '$Domain' NOT found in SANs"
        Write-Info "  Expected: $Domain"
        Write-Info "  Found: $($sanList -join ', ')"
    }
} else {
    Write-Warning "No Subject Alternative Names extension found"
    Write-Info "Checking if CN matches domain..."
    if ($subjectCN -eq $Domain) {
        Write-Success "✓ CN matches domain"
    } else {
        Write-Warning "⚠ CN does not match domain"
        Write-Info "  Expected: $Domain"
        Write-Info "  Got: $subjectCN"
    }
}

Write-Host ""

# Step 5: Check certificate chain
Write-Host "[5/7] Checking certificate chain..." -ForegroundColor Yellow
try {
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
    $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::AllowUnknownCertificateAuthority
    
    $isValid = $chain.Build($cert)
    $chainLength = $chain.ChainElements.Count

    Write-Info "Chain length: $chainLength certificate(s)"

    for ($i = 0; $i -lt $chain.ChainElements.Count; $i++) {
        $element = $chain.ChainElements[$i]
        $certInChain = $element.Certificate
        $depth = if ($i -eq 0) { "└─ Leaf" } else { "   ├─" }
        Write-Host "$depth [$i] $($certInChain.Subject)" -ForegroundColor Cyan
        
        if ($i -lt $chain.ChainElements.Count - 1) {
            Write-Info "     Issuer: $($certInChain.Issuer)"
        }
    }

    if ($isValid) {
        Write-Success "✓ Chain is valid"
    } else {
        Write-Warning "⚠ Chain validation failed"
        foreach ($status in $chain.ChainStatus) {
            Write-Info "  Status: $($status.Status) - $($status.StatusInformation)"
        }
    }
} catch {
    Write-Warning "⚠ Could not build full chain (may be normal for self-signed): $_"
    Write-Info "Certificate Subject: $($cert.Subject)"
    Write-Info "Certificate Issuer: $($cert.Issuer)"
    $chain = $null
}

Write-Host ""

# Step 6: Check Root CA trust
Write-Host "[6/7] Checking Root CA trust status..." -ForegroundColor Yellow

try {
    # Get root certificate from chain
    $rootCert = if ($chain -and $chain.ChainElements.Count -gt 0) {
        $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
    } else {
        # If no chain, use the certificate itself (self-signed case)
        $cert
    }
    
    Write-Info "Root CA: $($rootCert.Subject)"
    Write-Info "Root CA Thumbprint: $($rootCert.Thumbprint)"

    # Check if root CA is in trusted store
    $trustedStores = @(
        @{ Name = "LocalMachine\Root"; Path = "Cert:\LocalMachine\Root" },
        @{ Name = "CurrentUser\Root"; Path = "Cert:\CurrentUser\Root" }
    )

    $isTrusted = $false
    foreach ($store in $trustedStores) {
        $trustedCerts = Get-ChildItem -Path $store.Path -ErrorAction SilentlyContinue | 
            Where-Object { $_.Thumbprint -eq $rootCert.Thumbprint }
        
        if ($trustedCerts) {
            Write-Success "✓ Root CA is in $($store.Name)"
            $isTrusted = $true
            break
        }
    }

    if (-not $isTrusted) {
        Write-Warning "⚠ Root CA is NOT in any Trusted Root store"
        Write-Info "Root CA Path: ./certs/root_ca.crt"
        Write-Host ""
        Write-Host "To trust the Root CA system-wide, run (requires admin):" -ForegroundColor Yellow
        Write-Host "  certutil -addstore -f `"ROOT`" `"./certs/root_ca.crt`"" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Or import manually in Windows Settings > Certificates" -ForegroundColor Yellow
    }
} catch {
    Write-Warning "⚠ Could not verify Root CA trust: $_"
    $isTrusted = $false
}

Write-Host ""

# Step 7: Certificate signature algorithm
Write-Host "[7/7] Checking certificate signature algorithm..." -ForegroundColor Yellow
Write-Info "Signature Algorithm: $($cert.SignatureAlgorithm.FriendlyName)"
Write-Info "Key Size: $($cert.PublicKey.Key.KeySize) bits"
Write-Info "Key Algorithm: $($cert.PublicKey.Oid.FriendlyName)"

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "Certificate Validation Complete" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "Summary:" -ForegroundColor Cyan
[System.Collections.ArrayList]$issues = @()

Write-Host "  ✓ Certificate Retrieved" -ForegroundColor Green

if ($now -le $notAfter) {
    Write-Host "  ✓ Not Expired" -ForegroundColor Green
} else {
    Write-Host "  ✗ Expired" -ForegroundColor Red
    $issues.Add("Certificate is expired") | Out-Null
}

$domainFound = $false
if ($sanExtension) {
    $sanData = $sanExtension.Format($false)
    if ($sanData -match [regex]::Escape($Domain)) {
        Write-Host "  ✓ Domain in SANs" -ForegroundColor Green
        $domainFound = $true
    } else {
        Write-Host "  ✗ Domain NOT in SANs" -ForegroundColor Red
        $issues.Add("Domain '$Domain' not in certificate SANs") | Out-Null
    }
} else {
    if ($subjectCN -eq $Domain) {
        Write-Host "  ✓ Domain matches CN" -ForegroundColor Green
        $domainFound = $true
    } else {
        Write-Host "  ✗ Domain mismatch" -ForegroundColor Red
        $issues.Add("Domain '$Domain' doesn't match certificate CN '$subjectCN'") | Out-Null
    }
}

if ($isTrusted) {
    Write-Host "  ✓ Root CA Trusted" -ForegroundColor Green
} else {
    Write-Host "  ✗ Root CA NOT Trusted" -ForegroundColor Red
    $issues.Add("Root CA not in trusted store") | Out-Null
}

Write-Host ""

# Browser compatibility issues
if ($issues.Count -gt 0) {
    Write-Host "Issues that will affect browser access:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  ✗ $issue" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Fixes:" -ForegroundColor Yellow
    
    if ($issues -match "Root CA not") {
        Write-Host "  1. Trust the Root CA:" -ForegroundColor White
        Write-Host "     certutil -addstore -f `"ROOT`" `"./certs/root_ca.crt`"" -ForegroundColor Cyan
    }
    
    if ($issues -match "not in") {
        Write-Host "  2. Regenerate certificate for your domain:" -ForegroundColor White
        Write-Host "     .\generate-certs-vault.ps1 -Domain `"$Domain`"" -ForegroundColor Cyan
    }
    
    Write-Host "  3. Clear browser cache, close all browser tabs, and try again" -ForegroundColor White
} else {
    Write-Host "✓ No issues found - certificate should work with browsers" -ForegroundColor Green
}

Write-Host ""
