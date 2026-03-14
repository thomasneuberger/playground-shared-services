# 🔐 Zertifikatsinfrastruktur (PKI) mit Vault PKI Engine

Dieses Setup integriert **HashiCorp Vault PKI Engine** als Private Key Infrastructure für SSL/TLS und Client-Zertifikate.

## 🌟 Komponenten

- **Vault** (Port 8201) - Secret Management & PKI Engine
- **Root CA** - Root Certificate Authority (intern generiert)
- **Intermediate CA** - Intermediate CA für die Ausstellung von Zertifikaten
- **PKI Roles** - Vordefinierte Rollen für verschiedene Zertifikatstypen

## 📋 Verfügbare Certificate Roles

| Role | Verwendung | Server Flag | Client Flag | Max TTL |
|------|------------|-------------|-------------|---------|
| `server-cert` | HTTPS/TLS Server | ✓ | ✗ | 8760h (1 Jahr) |
| `client-cert` | Client-Authentifizierung | ✗ | ✓ | 8760h (1 Jahr) |
| `service-cert` | Service-to-Service (mTLS) | ✓ | ✓ | 8760h (1 Jahr) |

## 🚀 Schnelleinstieg

### 1. Umgebungsvariablen anpassen (optional)

```bash
# .env Datei anpassen
VAULT_TOKEN=MeinSicheresToken!
PKI_COMMON_NAME=My Organization Root CA
PKI_ORG=My Organization
PKI_TTL=87600h  # 10 Jahre für Root CA
```

### 2. Vault & PKI starten

```bash
# Vault und PKI Initialization starten
docker compose up -d vault vault-pki-init

# Logs checken
docker compose logs -f vault-pki-init

# Warten bis Initialisierung abgeschlossen ist
docker compose ps vault-pki-init
```

### 3. Root CA Zertifikat exportieren

Das Root CA Zertifikat wird automatisch nach `./certs/root_ca.crt` exportiert.

```bash
# Root CA anzeigen
cat ./certs/root_ca.crt

# Oder manuell exportieren
docker compose run --rm vault-pki-init
```

### 4. Vault Health Check

```bash
# Vault Status prüfen
docker compose exec vault vault status

# PKI Engine prüfen
docker compose exec vault vault secrets list
```

## 📦 Zertifikate generieren

### Option 1: PowerShell Script (Windows) ⭐ Empfohlen

```powershell
# Server-Zertifikat für localhost
.\scripts\generate-certs-vault.ps1 -Domain "localhost"

# Server-Zertifikat mit IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "myapp.local" -IpSans "192.168.1.10,127.0.0.1"

# Client-Zertifikat
.\scripts\generate-certs-vault.ps1 -CommonName "user@example.com" -Role "client-cert"

# Service-Zertifikat (Server + Client)
.\scripts\generate-certs-vault.ps1 -Domain "myservice.local" -Role "service-cert"

# Root CA exportieren
.\scripts\generate-certs-vault.ps1 -ExportRootCA
```

**💡 Hinweis**: Die generierten `.crt` Dateien enthalten automatisch die komplette Zertifikat-Chain (Leaf + Root CA), 
so dass Server-Anwendungen die Chain direkt an Clients übermitteln können.

### Option 2: Bash Script (Linux/macOS)

```bash
# Ausführbar machen
chmod +x scripts/generate-certs-vault.sh

# Server-Zertifikat für localhost
./scripts/generate-certs-vault.sh -d localhost

# Server-Zertifikat mit IP SANs
./scripts/generate-certs-vault.sh -d myapp.local -i "192.168.1.10,127.0.0.1"

# Client-Zertifikat
./scripts/generate-certs-vault.sh -c "user@example.com" -r client-cert

# Service-Zertifikat (Server + Client)
./scripts/generate-certs-vault.sh -d myservice.local -r service-cert

# Root CA exportieren
./scripts/generate-certs-vault.sh --root-ca
```

### Option 3: Vault CLI direkt

```bash
# Vault Environment setzen
export VAULT_ADDR="http://localhost:8201"
export VAULT_TOKEN="<your-token>"

# Server-Zertifikat generieren
vault write -format=json pki_int/issue/server-cert \
    common_name="myapp.local" \
    alt_names="myapp.local,www.myapp.local" \
    ip_sans="127.0.0.1" \
    ttl="8760h" > cert_data.json

# Zertifikat extrahieren
cat cert_data.json | jq -r '.data.certificate' > myapp.crt
cat cert_data.json | jq -r '.data.private_key' > myapp.key
cat cert_data.json | jq -r '.data.ca_chain[]' > myapp-ca-chain.crt
```

### Option 4: HTTP API

```bash
# Mit curl
curl -X POST \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -d '{
      "common_name": "myapp.local",
      "alt_names": "myapp.local",
      "ttl": "8760h"
    }' \
    http://localhost:8201/v1/pki_int/issue/server-cert
```

## 🔒 Client Zertifikate (mTLS)

### Client-Zertifikat generieren

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -CommonName "app-client@example.com" -Role "client-cert"
```

```bash
# Linux/macOS
./scripts/generate-certs-vault.sh -c "app-client@example.com" -r client-cert
```

### In .NET Core verwenden

```csharp
var handler = new HttpClientHandler();
handler.ClientCertificates.Add(
    new X509Certificate2("./certs/app-client@example.com.crt", "")
);

var client = new HttpClient(handler);
```

## 🏢 Batch-Zertifikate erstellen

### PowerShell

```powershell
$domains = @("app1.local", "app2.local", "app3.local")

foreach ($domain in $domains) {
    .\scripts\generate-certs-vault.ps1 -Domain $domain
    Write-Host "Generated certificate for $domain" -ForegroundColor Green
}
```

### Bash

```bash
#!/bin/bash
DOMAINS=("app1.local" "app2.local" "app3.local")

for domain in "${DOMAINS[@]}"; do
    ./scripts/generate-certs-vault.sh -d "$domain"
    echo "Generated certificate for $domain"
done
```

## 🔧 Erweiterte Konfiguration

### Neue PKI Role erstellen

```bash
docker compose exec vault vault write pki_int/roles/my-custom-role \
    allowed_domains="mycompany.local" \
    allow_subdomains=true \
    max_ttl="720h" \
    key_bits=2048 \
    server_flag=true \
    client_flag=false
```

### Certificate Policy anpassen

```bash
# TTL für eine Role ändern
docker compose exec vault vault write pki_int/roles/server-cert \
    max_ttl="4380h" \
    ttl="2190h"

# Allowed domains erweitern
docker compose exec vault vault write pki_int/roles/server-cert \
    allowed_domains="localhost,*.local,*.mycompany.com" \
    allow_subdomains=true
```

### Root CA erneuern

```bash
# Neues Root CA generieren
docker compose exec vault vault write -format=json pki/root/generate/internal \
    common_name="My New Root CA" \
    ttl=87600h \
    > new_root_ca.json

# Certificate extrahieren
cat new_root_ca.json | jq -r '.data.certificate' > ./certs/new_root_ca.crt
```

## 🖥️ CA Zertifikat vertrauen

### Windows

```powershell
# Als Administrator
certutil -addstore -f "ROOT" ".\certs\root_ca.crt"

# Verify
certutil -store ROOT | Select-String "Shared Services"
```

### Linux (Debian/Ubuntu)

```bash
sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/shared-services-ca.crt
sudo update-ca-certificates
```

### Linux (RHEL/CentOS)

```bash
sudo cp ./certs/root_ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

### macOS

```bash
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    ./certs/root_ca.crt
```

### Browser (Firefox)

Firefox verwendet eigenen Certificate Store:
1. Settings → Privacy & Security → Certificates → View Certificates
2. Authorities → Import
3. `./certs/root_ca.crt` wählen
4. "Trust this CA to identify websites" aktivieren

## 📊 Certificate Management

### Aktive Zertifikate auflisten

```bash
docker compose exec vault vault list pki_int/certs
```

### Zertifikat Details anzeigen

```bash
docker compose exec vault vault read pki_int/cert/<serial>
```

### Zertifikat widerrufen

```bash
docker compose exec vault vault write pki_int/revoke \
    serial_number="<serial>"
```

### CRL (Certificate Revocation List) abrufen

```bash
curl http://localhost:8201/v1/pki_int/crl -o crl.pem
openssl crl -in crl.pem -text -noout
```

## 🔄 Certificate Rotation

### Automatische Rotation mit cron (Linux)

```bash
# /etc/cron.d/cert-rotation
0 0 1 * * /path/to/generate-certs-vault.sh -d myapp.local && systemctl reload nginx
```

### PowerShell Scheduled Task (Windows)

```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-File "C:\path\to\generate-certs-vault.ps1" -Domain "myapp.local"'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 2am

Register-ScheduledTask -Action $action -Trigger $trigger `
    -TaskName "Certificate Rotation" -Description "Rotate SSL certificates"
```

## 🐛 Troubleshooting

### PKI Engine nicht initialisiert

```bash
# PKI Init Container neu starten
docker compose up -d vault-pki-init

# Logs prüfen
docker compose logs -f vault-pki-init
```

### Vault nicht erreichbar

```bash
# Vault Status prüfen
docker compose ps vault
docker compose logs vault

# Vault neu starten
docker compose restart vault
```

### Certificate Generation fehlgeschlagen

```bash
# Vault Token prüfen
docker compose exec vault vault token lookup

# PKI Role prüfen
docker compose exec vault vault read pki_int/roles/server-cert

# PKI Health Check
docker compose exec vault vault read pki_int/cert/ca
```

### "Permission Denied" Fehler

```bash
# Vault Token neu setzen
export VAULT_TOKEN="<your-token>"

# Oder in PowerShell
$env:VAULT_TOKEN="<your-token>"
```

## 📚 Weitere Ressourcen

- [Vault PKI Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [Vault API Documentation](https://developer.hashicorp.com/vault/api-docs/secret/pki)
- [Certificate Best Practices](https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine)

## 🎯 Best Practices

1. **Root CA sicher aufbewahren**: Root CA sollte offline gespeichert werden
2. **Kurze TTLs verwenden**: Intermediate Certificates mit kürzeren Laufzeiten
3. **Certificate Rotation**: Regelmäßige Erneuerung vor Ablauf
4. **Monitoring**: Alerts für ablaufende Zertifikate einrichten
5. **Backup**: Vault PKI Secrets regelmäßig sichern
6. **Least Privilege**: Nur notwendige Permissions für Certificate Issuance

## ⚠️ Sicherheitshinweise

- ✅ Root CA Token niemals committen
- ✅ Vault Token rotieren bei Verdacht auf Kompromittierung
- ✅ CRL regelmäßig prüfen
- ✅ Audit Logs aktivieren und überwachen
- ✅ Network Policies für Vault Container konfigurieren
- ✅ Production: Vault im Server-Modus (nicht -dev) betreiben
