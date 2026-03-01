# Zertifikat Management Scripts

Dieses Verzeichnis enthält hilfreiche Scripts zur Verwaltung von Zertifikaten mit **HashiCorp Vault PKI Engine**.

## 📄 Verfügbare Scripts

### ✅ Vault PKI Scripts (Aktuell)

- `generate-certs-vault.ps1` - Zertifikatgenerierung (Windows PowerShell)
- `generate-certs-vault.sh` - Zertifikatgenerierung (Linux/macOS)

### 📜 Legacy Scripts (Step CA)

Die folgenden Scripts sind für Step CA und werden nicht mehr aktiv verwendet:
- `generate-certs.ps1` - Legacy Step CA (Windows)
- `generate-certs.sh` - Legacy Step CA (Linux)
- `rotate-certs.sh` - Legacy Rotation

**Hinweis**: Die Legacy-Scripts bleiben für Referenzzwecke erhalten, sollten aber durch die neuen Vault PKI Scripts ersetzt werden.

---

## 🚀 Vault PKI Scripts

### 1. `generate-certs-vault.ps1` (Windows PowerShell) ⭐

Generiert Zertifikate über Vault PKI Engine mit umfangreichen Optionen.

#### Voraussetzungen
- Vault CLI installiert ([Download](https://www.vaultproject.io/downloads))
- Vault Service läuft (`docker compose up -d vault`)
- PKI initialisiert (`docker compose up -d vault-pki-init`)

#### Verwendung

**Server-Zertifikat generieren:**
```powershell
.\scripts\generate-certs-vault.ps1 -Domain "localhost"
```

**Server-Zertifikat mit IP SANs:**
```powershell
.\scripts\generate-certs-vault.ps1 -Domain "myapp.local" -IpSans "192.168.1.10,127.0.0.1"
```

**Client-Zertifikat generieren:**
```powershell
.\scripts\generate-certs-vault.ps1 -CommonName "user@example.com" -Role "client-cert"
```

**Service-Zertifikat (Server + Client):**
```powershell
.\scripts\generate-certs-vault.ps1 -Domain "myservice.local" -Role "service-cert"
```

**Root CA exportieren:**
```powershell
.\scripts\generate-certs-vault.ps1 -ExportRootCA
```

**Custom Vault Adresse:**
```powershell
.\scripts\generate-certs-vault.ps1 -Domain "myapp.local" -VaultAddr "http://192.168.1.100:8201" -VaultToken "your-token"
```

#### Parameter

| Parameter | Beschreibung | Erforderlich | Standard |
|-----------|--------------|--------------|----------|
| `-Domain` | Domain für Server-Zertifikat | Ja (für server/service) | - |
| `-CommonName` | CN für Client-Zertifikat | Ja (für client) | - |
| `-IpSans` | Komma-getrennte IP-Adressen | Nein | - |
| `-Role` | PKI Role (server-cert, client-cert, service-cert) | Nein | server-cert |
| `-VaultAddr` | Vault URL | Nein | http://localhost:8201 |
| `-VaultToken` | Vault Token | Nein | $env:VAULT_TOKEN oder myroot123 |
| `-OutputDir` | Ausgabeverzeichnis | Nein | ./certs |
| `-ExportRootCA` | Nur Root CA exportieren | Nein | false |

#### Output-Dateien

```
certs/
  ├── myapp.local.crt              # Server-Zertifikat mit CA Chain (für Server-TLS)
  ├── myapp.local.key              # Private Key
  ├── myapp.local-ca-chain.crt     # CA Chain (separat)
  ├── myapp.local-bundle.crt       # Komplettes Bundle (cert + chain)
  └── root_ca.crt                  # Root CA (für Client-seitige Verifikation)
```

**Wichtig**: Die `.crt` Datei enthält jetzt automatisch die komplette Zertifikat-Chain (Leaf + Root CA), so dass Server-Anwendungen (wie Traefik, Nginx, Vault) die Chain direkt an Clients übermitteln können. Das ermöglicht es Browsern, die Zertifikat-Vertrauenskette zu verifizieren.

#### Beispiel-Output

```
============================================================
  Vault PKI Certificate Generator (Windows)
============================================================

[INFO]  Certificate Type: server-cert
[INFO]  Certificate Name: myapp.local

[INFO]  Generating certificate from Vault PKI...
[OK]    Certificate with CA chain saved: ./certs/myapp.local.crt
[OK]    Private key saved: ./certs/myapp.local.key
[OK]    CA chain saved: ./certs/myapp.local-ca-chain.crt
[OK]    Certificate bundle saved: ./certs/myapp.local-bundle.crt

============================================================
✓ Certificate generated successfully!
============================================================

Files created:
  Certificate:    ./certs/myapp.local.crt (mit CA Chain)
  Private Key:    ./certs/myapp.local.key
  CA Chain:       ./certs/myapp.local-ca-chain.crt
  Bundle:         ./certs/myapp.local-bundle.crt

[INFO]  Serial Number: 4a:f8:6d:...
[INFO]  Expiration: 1735689600

Next steps:
  1. Trust the Root CA on your system:
     certutil -addstore -f "ROOT" ".\certs\root_ca.crt"

  2. Use in your application/server:
     Certificate: ./certs/myapp.local.crt (enthält bereits die CA Chain!)
     Private Key: ./certs/myapp.local.key
     
  3. Reload/Restart die Server-Anwendung (z.B. Traefik, Nginx, Vault)
     damit sie das neue Zertifikat mit Chain lädt
```

---

### 2. `generate-certs-vault.sh` (Linux/macOS)

Equivalent zum PowerShell-Script für Unix-basierte Systeme.

#### Voraussetzungen
- Vault CLI installiert
- Bash Shell
- Optional: `jq` für besseres JSON-Parsing

#### Verwendung

**Executable machen:**
```bash
chmod +x scripts/generate-certs-vault.sh
```

**Server-Zertifikat generieren:**
```bash
./scripts/generate-certs-vault.sh -d localhost
```

**Server-Zertifikat mit IP SANs:**
```bash
./scripts/generate-certs-vault.sh -d myapp.local -i "192.168.1.10,127.0.0.1"
```

**Client-Zertifikat generieren:**
```bash
./scripts/generate-certs-vault.sh -c "user@example.com" -r client-cert
```

**Service-Zertifikat (Server + Client):**
```bash
./scripts/generate-certs-vault.sh -d myservice.local -r service-cert
```

**Root CA exportieren:**
```bash
./scripts/generate-certs-vault.sh --root-ca
```

**Custom Vault Adresse:**
```bash
export VAULT_ADDR="http://192.168.1.100:8201"
export VAULT_TOKEN="your-token"
./scripts/generate-certs-vault.sh -d myapp.local
```

#### Optionen

| Option | Beschreibung | Erforderlich |
|--------|--------------|--------------|
| `-d, --domain` | Domain für Server-Zertifikat | Ja (für server/service) |
| `-c, --common-name` | CN für Client-Zertifikat | Ja (für client) |
| `-i, --ip-sans` | Komma-getrennte IPs | Nein |
| `-r, --role` | PKI Role | Nein (default: server-cert) |
| `-a, --vault-addr` | Vault URL | Nein |
| `-t, --vault-token` | Vault Token | Nein |
| `-o, --output-dir` | Ausgabeverzeichnis | Nein |
| `--root-ca` | Nur Root CA exportieren | Nein |
| `-h, --help` | Hilfe anzeigen | Nein |

---

## 📋 Häufige Anwendungsfälle

### 1. Lokale Entwicklung (localhost)

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "localhost" -IpSans "127.0.0.1"
```

```bash
# Linux/macOS
./scripts/generate-certs-vault.sh -d localhost -i "127.0.0.1"
```

### 2. Mehrere Domains (Batch)

**Windows:**
```powershell
$domains = @("app1.local", "app2.local", "app3.local")
foreach ($domain in $domains) {
    .\scripts\generate-certs-vault.ps1 -Domain $domain
}
```

**Linux/macOS:**
```bash
for domain in app1.local app2.local app3.local; do
    ./scripts/generate-certs-vault.sh -d $domain
done
```

### 3. mTLS Setup (Server + Client)

```powershell
# Server Certificate
.\scripts\generate-certs-vault.ps1 -Domain "api.myapp.local" -Role "service-cert"

# Client Certificate
.\scripts\generate-certs-vault.ps1 -CommonName "client-app@myapp.local" -Role "client-cert"
```

### 4. NAS/Container Environment

```powershell
# Mit spezifischer IP
.\scripts\generate-certs-vault.ps1 -Domain "nas.local" -IpSans "192.168.1.100"
```

### 5. Kubernetes/Service Mesh

```bash
# Service Certificate mit Multiple SANs
./scripts/generate-certs-vault.sh \
    -d myservice.default.svc.cluster.local \
    -r service-cert
```

---

## 🔧 Vault CLI Alternativen

Wenn die Scripts nicht verfügbar sind, können Zertifikate auch direkt über Vault CLI generiert werden:

### Server-Zertifikat

```bash
export VAULT_ADDR="http://localhost:8201"
export VAULT_TOKEN="myroot123"

vault write -format=json pki_int/issue/server-cert \
    common_name="myapp.local" \
    alt_names="myapp.local" \
    ip_sans="127.0.0.1" \
    ttl="8760h" > cert.json

# Zertifikat extrahieren
cat cert.json | jq -r '.data.certificate' > myapp.local.crt
cat cert.json | jq -r '.data.private_key' > myapp.local.key
```

### Client-Zertifikat

```bash
vault write -format=json pki_int/issue/client-cert \
    common_name="user@example.com" \
    ttl="8760h" > cert.json

cat cert.json | jq -r '.data.certificate' > client.crt
cat cert.json | jq -r '.data.private_key' > client.key
```

### Root CA exportieren

```bash
vault read -field=certificate pki/cert/ca > root_ca.crt
```

---

## 🔄 Certificate Rotation

### Manuell

Einfach das Script erneut ausführen - es überschreibt die alten Zertifikate:

```powershell
.\scripts\generate-certs-vault.ps1 -Domain "myapp.local"
```

### Automatisch (Windows Task Scheduler)

```powershell
$action = New-ScheduledTaskAction `
    -Execute 'PowerShell.exe' `
    -Argument '-File "C:\path\to\generate-certs-vault.ps1" -Domain "myapp.local"'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 2am

Register-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -TaskName "Cert Rotation - myapp.local" `
    -User "SYSTEM"
```

### Automatisch (Linux Cron)

```bash
# /etc/cron.d/cert-rotation
0 2 * * 1 /path/to/generate-certs-vault.sh -d myapp.local && systemctl reload nginx
```

---

## 🐛 Troubleshooting

### Problem: "Vault CLI not found"

**Lösung:**
```powershell
# Windows (Chocolatey)
choco install vault

# Windows (Manual)
# Download von https://www.vaultproject.io/downloads
```

```bash
# macOS
brew install vault

# Linux (Debian/Ubuntu)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```

### Problem: "Connection refused" / "Vault nicht erreichbar"

**Prüfung:**
```bash
docker compose ps vault
docker compose logs vault
```

**Lösung:**
```bash
# Vault starten
docker compose up -d vault vault-pki-init

# Vault Adresse prüfen
curl http://localhost:8201/v1/sys/health
```

### Problem: "Permission denied" / "Invalid token"

**Lösung:**
```powershell
# Token aus .env lesen
$env:VAULT_TOKEN = "YourTokenHere"

# Oder direkt im Script
.\scripts\generate-certs-vault.ps1 -Domain "myapp.local" -VaultToken "YourTokenHere"
```

### Problem: "PKI not initialized" / "No handler for route"

**Lösung:**
```bash
# PKI Init Service prüfen
docker compose ps vault-pki-init
docker compose logs vault-pki-init

# Neu initialisieren
docker compose up -d vault-pki-init
```

---

## � Certificate Chain - Wichtig für Server-TLS

Seit der letzten Aktualisierung enthalten die generierten `.crt` Dateien automatisch die komplette Zertifikat-Chain:

```
myapp.local.crt = [Leaf Certificate] + [Root CA Certificate]
```

Dies ist **kritisch wichtig** für Server-Anwendungen (Traefik, Nginx, Apache, Vault, etc.):

- **Ohne Chain**: Browser können die Vertrauenskette nicht verifizieren → SSL-Fehler
- **Mit Chain**: Browser erhalten die komplette Chain vom Server → Verifikation funktioniert ✓

### Beispiel-Szenario: Traefik + Vault

**Bevor der Fix:**
1. Genarier: `myapp.local.crt` (nur Leaf)
2. Traefik lädt: `myapp.local.crt` (nur Leaf)
3. Browser: "Root CA not found" → ❌ Fehler

**Nach dem Fix:**
1. Genarier: `myapp.local.crt` (Leaf + Root CA)
2. Traefik lädt: `myapp.local.crt` (Leaf + Root CA)
3. Browser: Empfängt komplette Chain → ✓ Verifikation OK

### Verifizierung der Chain

Um zu prüfen, dass deine `.crt` Datei die Chain enthält:

```powershell
# PowerShell - Chain anzeigen
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2("./certs/myapp.local.crt")
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chain.Build($cert)
$chain.ChainElements | Select-Object Certificate | Format-Table -AutoSize
```

```bash
# Bash - Zei Count der PEM-Blöcke (sollte >1 sein)
grep -c "BEGIN CERTIFICATE" ./certs/myapp.local.crt  # Sollte: 2 (oder mehr)
```

---

## �📚 Weiterführende Links

- [PKI_SETUP_VAULT.md](../PKI_SETUP_VAULT.md) - Detaillierte PKI Dokumentation
- [VAULT_PKI_MIGRATION.md](../VAULT_PKI_MIGRATION.md) - Migration von Step CA
- [Vault PKI Documentation](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [Vault CLI Reference](https://developer.hashicorp.com/vault/docs/commands)

---

## 💡 Tipps

1. **Vault Token**: Setze `VAULT_TOKEN` als Umgebungsvariable, um nicht jedes Mal den Token angeben zu müssen
2. **Directory**: Scripts können von überall ausgeführt werden, Zertifikate landen immer im `-OutputDir`
3. **Root CA**: Einmal vertrauen, dann funktionieren alle generierten Zertifikate
4. **Wildcards**: Verwende `*.myapp.local` für Wildcard-Zertifikate (wenn Role es erlaubt)
5. **Monitoring**: Notiere Serial Numbers für späteres Revocation-Management

---

**Letzte Aktualisierung**: Nach Migration zu Vault PKI Engine
