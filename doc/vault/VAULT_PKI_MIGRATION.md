# ✅ Vault PKI Integration - Zusammenfassung

## Was wurde geändert?

**Step CA wurde durch HashiCorp Vault PKI Engine ersetzt** für SSL/TLS und Client-Zertifikat-Verwaltung.

## 🔄 Migration von Step CA zu Vault PKI

### Entfernt
- ❌ `step-ca` Service (Port 9000)
- ❌ Step CA Konfigurationsdateien
- ❌ `STEP_CA_PASSWORD` und `STEP_CA_PROVISIONER_PASSWORD` Umgebungsvariablen
- ❌ `step-ca-data` Volume

### Hinzugefügt
- ✅ Vault PKI Engine Integration
- ✅ `vault-pki-init` Service für automatische PKI-Initialisierung
- ✅ Neue PKI-Umgebungsvariablen (`PKI_COMMON_NAME`, `PKI_ORG`, `PKI_TTL`)
- ✅ Vault PKI Initialization Script
- ✅ Neue Zertifikat-Generierungsskripte für Vault

## 📦 Aktualisierte Komponenten

### 1. **Vault Service** (Port 8201)

```yaml
# docker-compose.yml
vault:
  image: hashicorp/vault:latest
  environment:
    VAULT_TOKEN: <secure_token>
  volumes:
    - vault-data:/vault/data
    - vault-logs:/vault/logs
    - ./certs:/vault/certs
```

**Features:**
- ✅ Secret Management
- ✅ PKI Engine (Root CA & Intermediate CA)
- ✅ Vordefinierte Certificate Roles
- ✅ HTTP API für Certificate Issuance
- ✅ Certificate Revocation & CRL
- ✅ Health Checks & Monitoring

### 2. **Vault PKI Init Service**

Automatische Initialisierung bei erstem Start:
- Aktiviert PKI Secrets Engine
- Generiert Root CA (4096-bit RSA)
- Erstellt Intermediate CA
- Konfiguriert 3 Certificate Roles:
  - `server-cert` - Server Certificates (HTTPS/TLS)
  - `client-cert` - Client Certificates (mTLS)
  - `service-cert` - Service Certificates (Server + Client)
- Exportiert Root CA nach `./certs/root_ca.crt`

### 3. **Neue Zertifikat-Verwaltungsskripte**

#### **generate-certs-vault.ps1** (Windows PowerShell) ⭐

```powershell
# Server-Zertifikat
.\scripts\generate-certs-vault.ps1 -Domain "myapp.local"

# Server-Zertifikat mit IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "app.local" -IpSans "192.168.1.10"

# Client-Zertifikat
.\scripts\generate-certs-vault.ps1 -CommonName "user@example.com" -Role "client-cert"

# Root CA exportieren
.\scripts\generate-certs-vault.ps1 -ExportRootCA
```

#### **generate-certs-vault.sh** (Linux/macOS)

```bash
# Server-Zertifikat
./scripts/generate-certs-vault.sh -d myapp.local

# Client-Zertifikat
./scripts/generate-certs-vault.sh -c "user@example.com" -r client-cert

# Root CA exportieren
./scripts/generate-certs-vault.sh --root-ca
```

**Features:**
- ✅ Server & Client Certificates
- ✅ IP SANs Support
- ✅ Multiple Roles
- ✅ Automatischer Root CA Export
- ✅ Certificate Bundle Erstellung
- ✅ Farbige Ausgabe & Status-Meldungen

## 📋 Umgebungsvariablen (.env)

### Vorher (Step CA)
```bash
STEP_CA_PASSWORD=...
STEP_CA_PROVISIONER_PASSWORD=...
```

### Nachher (Vault PKI)
```bash
VAULT_TOKEN=...
PKI_COMMON_NAME=Shared Services Root CA
PKI_ORG=Shared Services
PKI_TTL=87600h
```

## 🚀 Quick Start

### 1. Services starten

```bash
# Alle Services starten (inklusive Vault PKI)
docker compose up -d

# Oder nur Vault und PKI Init
docker compose up -d vault vault-pki-init
```

### 2. PKI Initialisierung prüfen

```bash
# Logs anschauen
docker compose logs -f vault-pki-init

# Warten bis "✓ Vault PKI initialization completed!" erscheint
```

### 3. Root CA Zertifikat vertrauen

```powershell
# Windows (als Administrator)
certutil -addstore -f "ROOT" ".\certs\root_ca.crt"
```

```bash
# Linux
sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# macOS
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain ./certs/root_ca.crt
```

### 4. Erstes Zertifikat generieren

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "localhost"
```

```bash
# Linux/macOS
./scripts/generate-certs-vault.sh -d localhost
```

## 📊 Vergleich: Step CA vs. Vault PKI

| Feature | Step CA | Vault PKI |
|---------|---------|-----------|
| **Integration** | Separater Service | In Vault integriert |
| **Secret Management** | ❌ | ✅ |
| **HTTP API** | ✓ | ✓ |
| **Dynamic Secrets** | ❌ | ✅ |
| **Multiple Auth Methods** | Begrenzt | ✅ Umfangreich |
| **Certificate Roles** | Provisioner | Roles |
| **Revocation** | ✓ | ✓ |
| **ACME Support** | ✓ | ✓ (mit Plugin) |
| **Enterprise Features** | ✓ (kostenpflichtig) | ✓ (kostenpflichtig) |
| **Ecosystem** | Smallstep | HashiCorp |

## 🎯 Vorteile der Vault PKI Migration

### ✅ Vereinfachte Architektur
- Ein Service weniger (Vault erfüllt Secret Store + PKI)
- Gemeinsame Authentication & Authorization
- Einheitliche Logging & Monitoring

### ✅ Bessere Integration
- Secrets und Certificates aus einer Quelle
- Konsistente API
- Native .NET/Go/Python Libraries

### ✅ Enterprise-Ready
- Dynamic Secrets
- Advanced Access Control (Policies, ACLs)
- Audit Logging
- Multi-Tenancy Support

### ✅ Flexibilität
- Mehrere PKI Engines parallel möglich
- Custom Certificate Policies
- Programmable via API

## 🔧 Anwendungsbeispiele

### .NET Core mit Vault PKI Certificate

```csharp
// Kestrel mit Vault PKI Certificate konfigurieren
builder.WebHost.ConfigureKestrel(serverOptions =>
{
    serverOptions.ConfigureHttpsDefaults(listenOptions =>
    {
        listenOptions.ServerCertificate = 
            new X509Certificate2("./certs/myapp.local.crt", "");
    });
});
```

### Node.js mit Vault PKI

```javascript
const https = require('https');
const fs = require('fs');

const options = {
  key: fs.readFileSync('./certs/myapp.local.key'),
  cert: fs.readFileSync('./certs/myapp.local.crt'),
  ca: fs.readFileSync('./certs/root_ca.crt')
};

https.createServer(options, app).listen(443);
```

### Python mit Vault PKI

```python
import ssl
import http.server

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('./certs/myapp.local.crt', './certs/myapp.local.key')

server = http.server.HTTPServer(('localhost', 443), handler)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
```

## 📚 Weiterführende Dokumentation

- **[PKI_SETUP_VAULT.md](PKI_SETUP_VAULT.md)** - Detaillierte Vault PKI Anleitung
- **[scripts/README.md](../scripts/README.md)** - Dokumentation der Zertifikatsskripte
- **[ARCHITECTURE.md](../ARCHITECTURE.md)** - Gesamtarchitektur

## 🐛 Troubleshooting

### Problem: PKI nicht initialisiert

```bash
# PKI Init Service prüfen
docker compose ps vault-pki-init
docker compose logs vault-pki-init

# Manuell neu initialisieren
docker compose up -d vault-pki-init
```

### Problem: Certificate Generation fehlschlägt

```bash
# Vault Token prüfen
echo $VAULT_TOKEN  # Linux/macOS
echo $env:VAULT_TOKEN  # PowerShell

# Vault Status prüfen
docker compose exec vault vault status

# PKI Roles prüfen
docker compose exec vault vault list pki_int/roles
```

### Problem: Root CA nicht gefunden

```bash
# Root CA manuell exportieren
docker compose exec vault vault read -field=certificate pki/cert/ca > ./certs/root_ca.crt
```

## ⚠️ Breaking Changes

### Alte Step CA Zertifikate

Bestehende Zertifikate von Step CA sind **nicht kompatibel** mit Vault PKI:
- ❌ Alte Zertifikate müssen neu generiert werden
- ❌ Root CA hat sich geändert → Clients müssen neue Root CA vertrauen
- ❌ Certificate Fingerprints sind unterschiedlich

### Migration Checklist

- [ ] Neue Root CA in allen Clients installieren
- [ ] Alle Server-Zertifikate neu generieren
- [ ] Alle Client-Zertifikate neu generieren
- [ ] Alte Step CA Zertifikate deaktivieren
- [ ] Applications auf neue Zertifikatspfade aktualisieren
- [ ] Monitoring & Alerts auf neue Vault API umstellen

## 🎉 Nächste Schritte

1. **Root CA vertrauen**: `certutil -addstore "ROOT" .\certs\root_ca.crt` (Windows)
2. **Zertifikate generieren**: `.\scripts\generate-certs-vault.ps1 -Domain "localhost"`
3. **In App integrieren**: Pfad zu `.crt` und `.key` in Application Config
4. **Monitoring einrichten**: Vault Metrics in Prometheus/Grafana
5. **Production Setup**: Vault in Server-Mode betreiben (nicht -dev)

---

**Hinweis**: Diese Migration erfordert das Neugenerieren aller Zertifikate und das Aktualisieren der Root CA in allen Clients!
