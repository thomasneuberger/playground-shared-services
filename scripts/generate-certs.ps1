# Generate certificates using Step CA - Windows Edition
# 
# Usage:
#   .\generate-certs.ps1                    # Interactive
#   .\generate-certs.ps1 -Domain myapp.local
#   .\generate-certs.ps1 -Domain app.local -Client client@example.com

param(
    [string]$Domain,
    [string]$Client,
    [string]$CaUrl = "http://localhost:9000",
    [string]$CertsDir = ".\certs",
    [switch]$RootCA,
    [switch]$Help
)

# Stop on error
$ErrorActionPreference = "Stop"

# Helper Functions
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "✖ $Message" -ForegroundColor Red
}

function Show-Help {
    @"
Step CA Zertifikat Generator (Windows)

USAGE:
  .\generate-certs.ps1                              # Interactive
  .\generate-certs.ps1 -Domain domain.local         # Server-Zertifikat
  .\generate-certs.ps1 -Domain domain.local -Client client@example.com
  .\generate-certs.ps1 -RootCA                      # Root CA exportieren
  .\generate-certs.ps1 -Help                        # Diese Hilfe anzeigen

PARAMETER:
  -Domain     Domain-Name für Server-Zertifikat
  -Client     Client-Name für Client-Zertifikat
  -CaUrl      Step CA Adresse (default: http://localhost:9000)
  -CertsDir   Zertifikatsverzeichnis (default: .\certs)
  -RootCA     Root CA exportieren
  -Help       Hilfe anzeigen

BEISPIELE:
  .\generate-certs.ps1 -Domain myapp.local
  .\generate-certs.ps1 -Domain api.local -Client "client@example.com"
  .\generate-certs.ps1 -RootCA

"@
}

function Test-StepCA {
    Write-Info "Überprüfe Step CA Erreichbarkeit..."
    
    try {
        $response = Invoke-WebRequest -Uri "$CaUrl/health" -Method GET -SkipCertificateCheck -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Info "Step CA ist erreichbar ✓"
            return $true
        }
    }
    catch {
        Write-Error "Step CA nicht erreichbar unter $CaUrl"
        Write-Error "$($_.Exception.Message)"
        return $false
    }
}

function Generate-ServerCert {
    param(
        [string]$DomainName,
        [string[]]$SANs
    )
    
    if ([string]::IsNullOrWhiteSpace($DomainName)) {
        Write-Error "Domain erforderlich"
        return $false
    }
    
    Write-Info "Generiere Server-Zertifikat für '$DomainName'..."
    
    # Build step command
    $stepCmd = @(
        "ca", "certificate",
        "--ca-url", $CaUrl,
        "--san", $DomainName,
        "--insecure",
        "--not-after", "2160h",
        $DomainName,
        "$CertsDir\$DomainName.crt",
        "$CertsDir\$DomainName.key"
    )
    
    # Add additional SANs
    if ($SANs -and $SANs.Count -gt 0) {
        foreach ($san in $SANs) {
            $stepCmd = $stepCmd[0..2] + @("--san", $san) + $stepCmd[3..($stepCmd.Count-1)]
        }
    }
    
    try {
        & "step" @stepCmd
        Write-Info "✓ Zertifikat: $CertsDir\$DomainName.crt"
        Write-Info "✓ Privater Schlüssel: $CertsDir\$DomainName.key"
        
        Write-Info ""
        Write-Info "Zertifikat-Details:"
        & step certificate inspect "$CertsDir\$DomainName.crt" --format json | ConvertFrom-Json | 
            Select-Object @{n='Subject';e={$_.subject}}, 
                          @{n='Valid From';e={$_.validFrom}},
                          @{n='Valid To';e={$_.validTo}},
                          @{n='SANs';e={$_.sanList -join ', '}} | Format-Table
        
        return $true
    }
    catch {
        Write-Error "Fehler beim Generieren des Server-Zertifikats: $($_.Exception.Message)"
        return $false
    }
}

function Generate-ClientCert {
    param(
        [string]$ClientName
    )
    
    if ([string]::IsNullOrWhiteSpace($ClientName)) {
        Write-Error "Client Name erforderlich"
        return $false
    }
    
    # Sanitize filename
    $filename = $ClientName -replace '@', '_' -replace ' ', '_'
    
    Write-Info "Generiere Client-Zertifikat für '$ClientName'..."
    
    try {
        & step ca certificate `
            --ca-url "$CaUrl" `
            --profile leaf `
            --insecure `
            --not-after 2160h `
            "$ClientName" `
            "$CertsDir\$filename.crt" `
            "$CertsDir\$filename.key"
        
        Write-Info "✓ Zertifikat: $CertsDir\$filename.crt"
        Write-Info "✓ Privater Schlüssel: $CertsDir\$filename.key"
        
        Write-Info ""
        Write-Info "Zertifikat-Details:"
        & step certificate inspect "$CertsDir\$filename.crt" --format json | ConvertFrom-Json |
            Select-Object @{n='Subject';e={$_.subject}},
                          @{n='Valid From';e={$_.validFrom}},
                          @{n='Valid To';e={$_.validTo}} | Format-Table
        
        return $true
    }
    catch {
        Write-Error "Fehler beim Generieren des Client-Zertifikats: $($_.Exception.Message)"
        return $false
    }
}

function Export-RootCA {
    Write-Info "Exportiere Root CA..."
    
    try {
        # Try Docker copy first
        $dockerOutput = docker cp shared-step-ca:/home/step/certs/root_ca.crt "$CertsDir\root_ca.crt" 2>&1
        
        if (Test-Path "$CertsDir\root_ca.crt") {
            Write-Info "✓ Root CA: $CertsDir\root_ca.crt"
            
            Write-Warning ""
            Write-Warning "WICHTIG: Root CA ins Windows Certificate Store laden:"
            Write-Warning ""
            Write-Warning "  `$cert = Get-Item -Path '.\certs\root_ca.crt'"
            Write-Warning "  Import-Certificate -FilePath `$cert.FullName -CertStoreLocation 'Cert:\LocalMachine\Root' -Confirm:`$false"
            Write-Warning ""
            Write-Warning "ODER als Administrator in der Powershell:"
            Write-Warning "  Import-Certificate -FilePath '$(Resolve-Path "$CertsDir\root_ca.crt")' \"
            Write-Warning "    -CertStoreLocation 'Cert:\LocalMachine\Root' -Confirm:`$false"
            Write-Warning ""
            
            return $true
        }
    }
    catch {
        Write-Warning "Docker copy fehlgeschlagen, versuche API..."
    }
    
    # Fallback: Try via Invoke-WebRequest
    try {
        Invoke-WebRequest -Uri "$CaUrl/roots.pem" `
            -OutFile "$CertsDir\root_ca.crt" `
            -SkipCertificateCheck
        
        Write-Info "✓ Root CA: $CertsDir\root_ca.crt"
        return $true
    }
    catch {
        Write-Error "Root CA konnte nicht exportiert werden: $($_.Exception.Message)"
        return $false
    }
}

function Show-Interactive {
    Write-Host ""
    Write-Host "=== Step CA Zertifikat Generator ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Was möchtest du generieren?"
    Write-Host "1) Server-Zertifikat für eine Domain"
    Write-Host "2) Client-Zertifikat"
    Write-Host "3) Beides (Server + Client)"
    Write-Host "4) Root CA exportieren"
    Write-Host ""
    
    $choice = Read-Host "Wähle (1-4)"
    
    switch ($choice) {
        "1" {
            $domain = Read-Host "Domain-Name (z.B. myapp.local)"
            $additionalSans = Read-Host "Alternative SANs (optional, kommagetrennt)"
            
            $sans = $null
            if (-not [string]::IsNullOrWhiteSpace($additionalSans)) {
                $sans = @($additionalSans -split ',' | ForEach-Object { $_.Trim() })
            }
            
            Generate-ServerCert -DomainName $domain -SANs $sans
        }
        "2" {
            $client = Read-Host "Client Name (z.B. client@example.com)"
            Generate-ClientCert -ClientName $client
        }
        "3" {
            $domain = Read-Host "Domain-Name (z.B. myapp.local)"
            $additionalSans = Read-Host "Alternative SANs (optional, kommagetrennt)"
            $client = Read-Host "Client Name (z.B. client@example.com)"
            
            $sans = $null
            if (-not [string]::IsNullOrWhiteSpace($additionalSans)) {
                $sans = @($additionalSans -split ',' | ForEach-Object { $_.Trim() })
            }
            
            Generate-ServerCert -DomainName $domain -SANs $sans
            Generate-ClientCert -ClientName $client
        }
        "4" {
            Export-RootCA
        }
        default {
            Write-Error "Ungültige Auswahl"
            exit 1
        }
    }
}

# Main Script
if ($Help) {
    Show-Help
    exit 0
}

# Check if step is installed
try {
    $null = & step version
}
catch {
    Write-Error "Step CLI nicht gefunden. Installiere es von: https://smallstep.com/docs/step-cli/installation/"
    exit 1
}

# Create certs directory
if (-not (Test-Path $CertsDir)) {
    New-Item -ItemType Directory -Path $CertsDir -Force | Out-Null
}

# Check Step CA connectivity
if (-not (Test-StepCA)) {
    exit 1
}

# Process commands
if ($RootCA) {
    Export-RootCA
}
elseif ([string]::IsNullOrWhiteSpace($Domain) -and [string]::IsNullOrWhiteSpace($Client)) {
    # Interactive mode
    Show-Interactive
}
else {
    # Command-line mode
    if (-not [string]::IsNullOrWhiteSpace($Domain)) {
        Write-Info "Generiere Server-Zertifikat für: $Domain"
        if (-not (Generate-ServerCert -DomainName $Domain)) {
            exit 1
        }
    }
    
    if (-not [string]::IsNullOrWhiteSpace($Client)) {
        Write-Info "Generiere Client-Zertifikat für: $Client"
        if (-not (Generate-ClientCert -ClientName $Client)) {
            exit 1
        }
    }
}

# Summary
Write-Host ""
Write-Info "Zertifikate erfolgreich generiert!"
Write-Host ""
Get-ChildItem -Path $CertsDir -File | Format-Table Name, Length, LastWriteTime
Write-Host ""
