# Zertifikat Management Scripts

Dieses Verzeichnis enthält hilfreiche Scripts zur Verwaltung von Zertifikaten mit **Step CA**.

## 📄 Scripts

### 1. `generate-certs.sh` / `generate-certs.ps1`
Generiert neue Zertifikate für Server und Clients.

**Linux/Mac:**
```bash
# Interaktiv
./scripts/generate-certs.sh

# Server-Zertifikat
./scripts/generate-certs.sh myapp.local

# Server + Client
./scripts/generate-certs.sh myapp.local "client@example.com"

# Root CA exportieren
./scripts/generate-certs.sh --root-ca
```

**Windows (PowerShell):**
```powershell
# Interaktiv
.\scripts\generate-certs.ps1

# Server-Zertifikat
.\scripts\generate-certs.ps1 -Domain myapp.local

# Server + Client
.\scripts\generate-certs.ps1 -Domain app.local -Client "client@example.com"

# Root CA exportieren
.\scripts\generate-certs.ps1 -RootCA
```

**Output:**
```
✓ Zertifikat: ./certs/myapp.local.crt
✓ Privater Schlüssel: ./certs/myapp.local.key
```

### 2. `rotate-certs.sh`
Überwacht Zertifikate und erneuert diese automatisch, wenn sie bald ablaufen.

**Einzelne Ausführung:**
```bash
./scripts/rotate-certs.sh
```

**Automatisch via Cron (täglich 2:00 Uhr):**
```bash
# Crontab öffnen
crontab -e

# Hinzufügen:
0 2 * * * cd /path/to/playground-shared-services && ./scripts/rotate-certs.sh
```

**Umgebungsvariablen:**
```bash
# Tage vor Ablauf erneuern (default: 30)
DAYS_BEFORE_EXPIRY=60 ./scripts/rotate-certs.sh

# Webhook Benachrichtigungen (Slack, Discord etc.)
WEBHOOK_URL="https://hooks.slack.com/services/..." ./scripts/rotate-certs.sh

# Custom Verzeichnis
CERTS_DIR=/etc/myapp/certs ./scripts/rotate-certs.sh
```

**Output:**
```
[2026-02-25 14:32:10] ℹ === Zertifikat Rotation gestartet ===
[2026-02-25 14:32:10] ℹ CA URL: http://localhost:9000
[2026-02-25 14:32:10] ⚠ myapp.crt läuft bald ab (28 Tage)
[2026-02-25 14:32:15] ✓ myapp.crt erneuert
[2026-02-25 14:32:15] ℹ === Rotation abgeschlossen ===
```

## 🔧 Voraussetzungen

### Linux / macOS
```bash
# Step CLI installieren
brew install smallstep/step/step

# Oder von https://smallstep.com/docs/step-cli/installation/

# Zusätzlich erforderlich:
# - openssl
# - curl
# - jq (optional, für JSON parsing)
```

### Windows (PowerShell)
```powershell
# Step CLI installieren
choco install step

# Oder von https://smallstep.com/docs/step-cli/installation/

# oder direkt mit scoop:
scoop install step
```

## 📝 Beispiel: Automated Certificate Management

### Scenario: Microservices mit mTLS

Angenommen, du hast folgende Services:
- `api.local` - API Server
- `auth.local` - Auth Service
- `worker.local` - Worker Service

**Setup:**
```bash
# 1. Server-Zertifikate generieren
./scripts/generate-certs.sh api.local
./scripts/generate-certs.sh auth.local
./scripts/generate-certs.sh worker.local

# 2. Client-Zertifikate generieren
./scripts/generate-certs.sh api.local "api-client@example.com"
./scripts/generate-certs.sh auth.local "auth-client@example.com"
./scripts/generate-certs.sh worker.local "worker-client@example.com"

# 3. Root CA exportieren
./scripts/generate-certs.sh --root-ca
```

**Automatische Rotation:**
```bash
# Cron Job einrichten
0 2 * * * cd /app && ./scripts/rotate-certs.sh >> logs/cert-rotation.log 2>&1

# Alert setzen wenn Rotation fehlschlägt
0 3 * * * grep "ERROR" /app/logs/cert-rotation.log | mail -s "Cert Rotation Failed" admin@example.com
```

### Scenario: Docker Compose Integration

```yaml
# docker-compose.yml
services:
  cert-manager:
    image: smallstep/step-ca:latest
    volumes:
      - ./certs:/home/step/certs:ro
    entrypoint: >
      bash -c "
      while true; do
        /path/to/rotate-certs.sh
        sleep 86400  # 24h
      done
      "
  
  api:
    image: myapp:latest
    volumes:
      - ./certs/api.local.crt:/app/certs/server.crt:ro
      - ./certs/api.local.key:/app/certs/server.key:ro
      - ./certs/root_ca.crt:/app/certs/ca.crt:ro
```

## 🔒 Sicherheits-Best-Practices

✅ **Zertifikats-Backups**
```bash
# Automatisches Backup vor Rotation
tar -czf "certs-backup-$(date +%Y%m%d-%H%M%S).tar.gz" certs/
```

✅ **Permissions setzen**
```bash
# Keys sollten nur vom Service lesbar sein
chmod 600 certs/*.key
chown 1000:1000 certs/*.key
```

✅ **Monitoring & Alerting**
```bash
# Überwachen ob Zertifikate bald ablaufen
WEBHOOK_URL="https://monitoring.example.com/alerts" ./scripts/rotate-certs.sh
```

✅ **Rotation vor Ablauf**
```bash
# Erneuere Zertifikate 60 Tage vor Ablauf
DAYS_BEFORE_EXPIRY=60 ./scripts/rotate-certs.sh
```

❌ **Nicht tun:**
- Keys in Git committen
- Certificates hardcoden
- Default Passwörter verwenden
- Rotation nicht automatisieren

## 🐛 Troubleshooting

### `step: command not found`
```bash
# Step CLI Check
which step
step version

# Installation überprüfen
brew info smallstep/step/step  # macOS
choco list step                  # Windows
which step                       # Linux
```

### `Certificate validation failed`
```bash
# Überprüfe SANs
step certificate inspect ./certs/myapp.local.crt | grep -i "san\|subject"

# Root CA neu laden (Windows)
Import-Certificate -FilePath ".\certs\root_ca.crt" `
  -CertStoreLocation "Cert:\LocalMachine\Root"
```

### Step CA nicht erreichbar
```bash
# Check Connectivity
curl -k http://localhost:9000/health

# Check Container
docker-compose logs step-ca
docker-compose exec step-ca step ca health --insecure
```

### Zertifikat erneuern fehlgeschlagen

```bash
# Manuelle Erneuerung
step ca renew ./certs/myapp.local.crt ./certs/myapp.local.key \
  --ca-url http://localhost:9000 \
  --insecure

# Oder neu generieren
./scripts/generate-certs.sh myapp.local
```

## 📊 Monitoring

### Prometheus Metriken
```bash
# Zertifikat-Ablauf in Prometheus exportieren
cat > /usr/local/bin/cert-exporter << 'EOF'
#!/bin/bash
for cert in /app/certs/*.crt; do
    name=$(basename "$cert" .crt)
    days=$(openssl x509 -in "$cert" -noout -checkend 86400 2>/dev/null | grep -o '[0-9]*' || echo "0")
    echo "cert_days_until_expiry{cert=\"$name\"} $days"
done
EOF

chmod +x /usr/local/bin/cert-exporter
```

### Grafana Alert
```
alert: CertificateExpiringSoon
expr: cert_days_until_expiry < 30
for: 1h
annotations:
  summary: "Certificate {{ $labels.cert }} expires in {{ $value }} days"
```

## 📚 Weitere Ressourcen

- [Step CA Dokumentation](https://smallstep.com/docs/step-ca/)
- [Small Step Blog - Certificates & mTLS](https://smallstep.com/blog/)
- [ACME Protocol RFC](https://tools.ietf.org/html/rfc8555)

## 💡 Tipps

- **Testen vor Production:** `--insecure` Flag nur in Entwicklung verwenden
- **Batch Operations:** SANs setzen beim Generieren um mehrere Domains zu schützen
- **Automation:** Cron/Kubernetes Jobs nutzen für automatische Rotation
- **Backup:** Regelmäßig Zertifikate und Keys sichern
- **Monitoring:** Ablaufdaten in Prometheus/Grafana tracken
