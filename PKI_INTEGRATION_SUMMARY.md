# ✅ Zertifikatsinfrastruktur Integration - Zusammenfassung

## Was wurde hinzugefügt?

Vollständige PKI (Private Key Infrastructure) mit **Step CA (Smallstep Certificates)** für SSL/TLS und Client-Zertifikat-Verwaltung.

## 📦 Neue Komponenten

### 1. **Step CA Service** (Port 9000)
```yaml
# docker-compose.yml
step-ca:
  image: smallstep/step-ca:latest
  environment:
    STEP_CA_PASSWORD: <secure_password>
  volumes:
    - step-ca-data:/home/step
```

**Features:**
- ✅ Root CA Management (selbstsigniert)
- ✅ Intermediate CA für Zertifikatsausstellung
- ✅ ACME-Protokoll Support
- ✅ Automatische Zertifizierung
- ✅ Health Checks & Monitoring

### 2. **Neue Skripte für Zertifikat-Verwaltung**

#### **generate-certs.sh** (Linux/macOS)
```bash
# Server-Zertifikat
./scripts/generate-certs.sh myapp.local

# Server + Client
./scripts/generate-certs.sh myapp.local "client@example.com"

# Root CA exportieren
./scripts/generate-certs.sh --root-ca
```

#### **generate-certs.ps1** (Windows PowerShell)
```powershell
# Server-Zertifikat
.\scripts\generate-certs.ps1 -Domain myapp.local

# Server + Client
.\scripts\generate-certs.ps1 -Domain app.local -Client "client@example.com"

# Root CA exportieren
.\scripts\generate-certs.ps1 -RootCA
```

#### **rotate-certs.sh** (Automatische Rotation)
```bash
# Einmalige Ausführung
./scripts/rotate-certs.sh

# Automatisch via Cron (täglich 2 Uhr)
0 2 * * * /path/to/rotate-certs.sh
```

## 📄 Neue Dokumentation

### 1. **PKI_SETUP.md** (Umfassender Guide)
- ✅ Step CA Installation & Konfiguration
- ✅ Zertifikat-Generierung (Server, Client, Batch)
- ✅ Root CA ins System Trust Store laden
- ✅ Zertifikat-Rotation & Monitoring
- ✅ Troubleshooting & Best Practices

### 2. **DOTNET_INTEGRATION.md** (Erweitert um HTTPS/mTLS)
- ✅ HTTPS Server mit Step CA Zertifikaten
- ✅ Mutual TLS (mTLS) - Client Authentifizierung
- ✅ Certificate Pinning für zusätzliche Sicherheit
- ✅ Health Checks für Zertifikat-Ablauf

### 3. **ARCHITECTURE.md** (Gesamtübersicht)
- ✅ System-Architektur-Diagramm
- ✅ Kommunikations-Flows (Auth, Messaging, Secrets, PKI, Observability)
- ✅ Certificate Lifecycle Visualisierung
- ✅ Port- und Netzwerk-Mapping

### 4. **scripts/README.md** (Script Dokumentation)
- ✅ Detaillierte Script-Beschreibungen
- ✅ Verwendungsbeispiele
- ✅ Docker Compose Integration
- ✅ Monitoring & Alerting Setup

## 🔐 Neue Konfigurationsdateien

```
config/step-ca/
├── init.json              # Step CA Konfiguration (minimal)
├── init-ca.sh            # CA Initialisierungs-Skript
└── entrypoint.sh         # Startup-Skript für Container

scripts/
├── generate-certs.sh     # Zertifikate generieren (Linux/macOS)
├── generate-certs.ps1    # Zertifikate generieren (Windows)
├── rotate-certs.sh       # Automatische Rotation
└── README.md             # Script-Dokumentation
```

## 🚀 Quick Start

### 1. Step CA starten
```bash
docker-compose up -d step-ca

# Health Check
docker-compose logs step-ca
```

### 2. Root CA exportieren & vertrauen
```bash
# Export
./scripts/generate-certs.sh --root-ca

# Windows: Import ins Trust Store
Import-Certificate -FilePath ".\certs\root_ca.crt" `
  -CertStoreLocation "Cert:\LocalMachine\Root"

# Linux/macOS: Siehe PKI_SETUP.md
```

### 3. Zertifikate generieren
```bash
# Server
./scripts/generate-certs.sh myapp.local

# Server + Client
./scripts/generate-certs.sh api.local "client@example.com"

# Batch für mehrere Services
for service in api auth worker; do
  ./scripts/generate-certs.sh $service.local
done
```

### 4. In ASP.NET Core integrieren

Siehe **DOTNET_INTEGRATION.md**:
- [HTTPS Server Setup](DOTNET_INTEGRATION.md#https-und-zertifikate-step-ca)
- [mTLS Client Authentication](DOTNET_INTEGRATION.md#mutual-tls-mtls---client-authentifizierung)
- [Certificate Health Checks](DOTNET_INTEGRATION.md#-health-checks-ausführen)

## 📊 Überwachung & Alerts

### Prometheus Metriken
```yaml
# prometheus.yml
- job_name: 'step-ca'
  static_configs:
    - targets: ['step-ca:9000']
  metrics_path: '/metrics'
```

### Health Checks
```bash
# Container Health
docker-compose ps step-ca

# API Health
curl -k http://localhost:9000/health

# Zertifikat-Ablauf überwachen
./scripts/rotate-certs.sh --check
```

## 🔄 Automatische Rotation

### Cron Job (Linux/macOS)
```bash
# Täglich um 2:00 Uhr prüfen & rotieren
0 2 * * * cd /path/to/shared-services && ./scripts/rotate-certs.sh >> logs/cert-rotation.log 2>&1

# Tägliche Alerting um 3:00 Uhr
0 3 * * * grep "ERROR" /path/to/logs/cert-rotation.log | mail -s "Cert Rotation Failed" admin@example.com
```

### Docker Compose (Service Rotation)
```yaml
services:
  cert-manager:
    image: alpine:latest
    volumes:
      - ./scripts:/scripts:ro
      - ./certs:/certs
    command: >
      sh -c "while true; do
        /scripts/rotate-certs.sh
        sleep 86400
      done"
    environment:
      CERTS_DIR: /certs
      CA_URL: http://step-ca:9000
```

## 🔒 Security Features

✅ **Automatische Zertifikat-Rotation**
- Rotiert Zertifikate 30 Tage vor Ablauf
- Vollständiges Rollback bei Fehler

✅ **mTLS Support**
- Client-Zertifikat Authentifizierung
- Service-to-Service sichere Kommunikation

✅ **Root CA Isolation**
- Private Root CA (offline verfügbar)
- Intermediate CA für täglichen Betrieb

✅ **System Trust Store Integration**
- Root CA in OS Trust Chain
- Keine selbstsignierte Zertifikat-Warnings

✅ **Backup & Recovery**
- Automatische Backups bei Rotation
- Fallback bei fehlgeschlagener Rotation

## 📝 Umgebungsvariablen

```bash
# docker-compose.yml / .env
STEP_CA_PASSWORD=secure_password
STEP_CA_PROVISIONER_PASSWORD=provisioner_password

# Sripts / rotate-certs.sh
CA_URL=http://localhost:9000
CERTS_DIR=./certs
DAYS_BEFORE_EXPIRY=30
WEBHOOK_URL=https://slack.example.com/hooks/  # Optional
LOG_FILE=./logs/cert-rotation.log
```

## 🔗 Integration Beispiele

### Szenario 1: Microservices mit mTLS
```
Jeder Service hat:
- Server Certificate (service.local.crt/key)
- Client Certificate (service-client.crt/key)
→ Authentifizierung zwischen Services
```

### Szenario 2: Grafana Dashboard Sicherung
```
- Grafana HTTPS aktivieren
- Client Cert für Datasource-Access
- Zertifikat-Ablauf als Alert
```

### Szenario 3: API Gateway mit mTLS
```
- Gateway listens on HTTPS mit Server Cert
- Clients benötigen Client Cert
- Automatische Rotation für alle
```

## 🎯 Nächste Schritte

1. ✅ **Step CA aktivieren** → `docker-compose up -d step-ca`
2. ✅ **Zertifikate generieren** → `./scripts/generate-certs.sh myapp.local`
3. ✅ **Root CA vertrauen** → OS Trust Store Import
4. ✅ **ASP.NET Integration** → Siehe DOTNET_INTEGRATION.md
5. ✅ **Rotation automatisieren** → Cron Job / Kubernetes CronJob
6. ✅ **Monitoring aktivieren** → Health Checks & Alerts in Grafana

## 📚 Weitere Ressourcen

- [Step CA Official Docs](https://smallstep.com/docs/step-ca/)
- [Step CLI Reference](https://smallstep.com/docs/step-cli/)
- [Mutual TLS Best Practices](https://smallstep.com/blog/mutually-authenticated-tls/)
- [ASP.NET HTTPS Documentation](https://docs.microsoft.com/en-us/aspnet/core/security/https)

## ❓ FAQ

**F: Was ist der Unterschied zwischen Root CA und Intermediate CA?**
A: Root CA ist offline und signiert die Intermediate CA. Intermediate CA wird täglich für Zertifikatsausstellung verwendet.

**F: Muss ich die Root CA ins System Trust Store laden?**
A: Ja, sonst erhalten Clients "untrusted certificate" Warnings.

**F: Wie oft sollte ich Zertifikate rotieren?**
A: Standard: 30 Tage vor Ablauf (konfig: `DAYS_BEFORE_EXPIRY=30`)

**F: Kann ich mTLS optional machen?**
A: Ja, mit `ClientCertificateMode = ClientCertificateMode.Optional` in Kestrel

**F: Was passiert bei Rotation-Fehler?**
A: Automatisches Rollback zum Backup, Webhook-Alert an Ops-Team

---

**Status**: ✅ Fertig zum Deployment
**Last Updated**: 2026-02-25
**Maintainer**: Shared Services Team
