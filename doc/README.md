# Shared Services - Detailed Operations Guide

Diese Datei enthält die detaillierten Service- und Betriebsanleitungen.

Für Repository-Überblick, Architektur-Zusammenfassung, Voraussetzungen und Quick Start siehe [../README.md](../README.md).

## 📊 Grafana Setup (beim ersten Start)

1. Öffne https://grafana.local:8443
2. Login mit Admin-Benutzer
3. Datasources sind bereits vorbereitet:
   - Prometheus (Metriken)
   - Loki (Logs)
   - Tempo (Traces)
4. Erstelle ein Dashboard oder führe Queries aus

### HTTPS-Konfiguration für Grafana (Traefik Gateway TLS Termination)

Grafana ist über HTTPS via den Traefik **Gateway** mit Vault PKI Zertifikaten konfiguriert.
Das Routing ist in `config/traefik/dynamic.yml` unter dem Router `grafana` definiert.

📖 **[GRAFANA_VAULT_HTTPS.md](./grafana/GRAFANA_VAULT_HTTPS.md)** - Vollständige Anleitung zur HTTPS-Konfiguration

Quick Start:
```powershell
# Zertifikat von Vault PKI generieren
.\scripts\generate-certs-vault.ps1 -Domain "grafana.local"

# Services neu starten (Traefik Gateway lädt das Zertifikat automatisch neu)
docker compose up -d
```

Dann über HTTPS zugreifen:
- https://grafana.local:8443

**Hinweis:** `grafana.local` muss in deiner `/etc/hosts` (Linux/macOS) oder `C:\Windows\System32\drivers\etc\hosts` (Windows) eingetragen sein:
```
127.0.0.1  grafana.local
```

## 🔐 Vault Setup (Initial)

```bash
# In den Vault Container gehen
docker compose exec vault sh

# Root Token verwenden (aus .env)
export VAULT_TOKEN=<VAULT_TOKEN>
# Dev Vault nutzt HTTP, daher Adresse explizit setzen
export VAULT_ADDR=http://127.0.0.1:8200

# Secrets erstellen
vault kv put secret/myapp/database \
  username=dbuser \
  password=dbpass

# Secrets lesen
vault kv get secret/myapp/database
```
## 🔐 Keycloak Setup (Initial)

Keycloak wird automatisch initialisiert. Admin-Zugriff über HTTPS via Traefik Gateway:

```bash
# 1. Öffne Keycloak Admin Console (HTTPS via Traefik Gateway)
# https://keycloak.local:8443/admin

# 2. Login mit Admin-Credentials (aus .env)
# admin / <KEYCLOAK_ADMIN_PASSWORD>

# 3. Realm erstellen
# - Administration Console → Realms → Create Realm
# - Name: myapp

# 4. Client für ASP.NET App registrieren
# - Clients → Create Client
# - Client ID: myapp
# - Client Protocol: openid-connect
# - Access Type: confidential
# - Valid Redirect URIs: http://localhost:YOUR_PORT/* (z.B. http://localhost:5001/*)
#                        https://keycloak.local/* (für HTTPS via Traefik)
```

### HTTPS-Konfiguration für Keycloak (Traefik Gateway TLS Termination)

Keycloak kann über HTTPS via den Traefik **Gateway** mit Vault PKI Zertifikaten konfiguriert werden.
Das Routing ist in `config/traefik/dynamic.yml` unter dem Router `keycloak` definiert.

📖 **[KEYCLOAK_VAULT_HTTPS.md](./keycloak/KEYCLOAK_VAULT_HTTPS.md)** - Vollständige Anleitung zur HTTPS-Konfiguration

Quick Start:
```powershell
# Zertifikat von Vault PKI generieren
.\scripts\generate-certs-vault.ps1 -Domain "keycloak.local"

# Services neu starten (Traefik Gateway lädt das Zertifikat automatisch neu)
docker compose up -d
```

Dann über HTTPS zugreifen:
- HTTPS: https://keycloak.local:8443/admin (über Traefik Gateway @ Port 8443)

**Hinweis:** Für HTTPS via Traefik Gateway muss `keycloak.local` in deiner `/etc/hosts` (Linux/macOS) oder `C:\Windows\System32\drivers\etc\hosts` (Windows) eingetragen sein, oder du nutzt einen echten DNS-Namen.

## 🔑 Vault PKI Setup

Vault PKI wird automatisch beim Start initialisiert. Für Zertifikatsverwaltung:

```bash
# Vault CLI installieren: https://www.vaultproject.io/downloads

# Zertifikat generieren (Windows PowerShell)
.\scripts\generate-certs-vault.ps1 -Domain "localhost"

# Zertifikat generieren (Linux/macOS)
./scripts/generate-certs-vault.sh -d localhost

# Root CA exportieren
.\scripts\generate-certs-vault.ps1 -ExportRootCA
```

**Wichtig**: Beim ersten Setup müssen Zertifikate für **alle** Domains inkl. `traefik.local` generiert werden:

```powershell
# Alle benötigten Zertifikate generieren (Windows PowerShell)
.\scripts\generate-certs-vault.ps1 -Domain "traefik.local"
.\scripts\generate-certs-vault.ps1 -Domain "vault.local"
.\scripts\generate-certs-vault.ps1 -Domain "keycloak.local"
.\scripts\generate-certs-vault.ps1 -Domain "grafana.local"
.\scripts\generate-certs-vault.ps1 -Domain "prometheus.local"
.\scripts\generate-certs-vault.ps1 -Domain "loki.local"
.\scripts\generate-certs-vault.ps1 -Domain "tempo.local"
```

```bash
# Alle benötigten Zertifikate generieren (Linux/macOS)
for domain in traefik.local vault.local keycloak.local grafana.local prometheus.local loki.local tempo.local; do
  ./scripts/generate-certs-vault.sh -d "$domain"
done
```

**Root CA im System Trust Store registrieren** (damit Browser das Zertifikat akzeptieren):

```powershell
# Windows (als Administrator)
certutil -addstore -f "ROOT" ".\certs\root_ca.crt"
```

```bash
# Linux
sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

Siehe [PKI_SETUP_VAULT.md](./vault/PKI_SETUP_VAULT.md) für detaillierte Dokumentation.

## �📨 RabbitMQ Setup

1. Öffne https://rabbit.local:15671
2. Login: guest / guest
3. Queues und Topics erstellen unter dem Punkt "Queues"

## 📝 Logs und Monitoring

### Prometheus Metrics sammeln

Prometheus ist über HTTPS via den Traefik **Gateway** verfügbar (Router `prometheus` in `config/traefik/dynamic.yml`):

📚 **[PROMETHEUS_VAULT_HTTPS.md](./prometheus/PROMETHEUS_VAULT_HTTPS.md)** - Vollständige Anleitung zur HTTPS-Konfiguration

Quick Start:
```powershell
# Zertifikat von Vault PKI generieren
.\scripts\generate-certs-vault.ps1 -Domain "prometheus.local"

# Services neu starten
docker compose up -d
```

Zugriff:
- **Web UI:** https://prometheus.local:8443
- **API:** `curl -k "https://prometheus.local:8443/api/v1/query?query=up"`

### Loki Logs durchsuchen

Loki ist über HTTPS via den Traefik **Gateway** verfügbar (Router `loki` in `config/traefik/dynamic.yml`):

📚 **[LOKI_VAULT_HTTPS.md](./loki/LOKI_VAULT_HTTPS.md)** - Vollständige Anleitung zur HTTPS-Konfiguration

Quick Start:
```powershell
# Zertifikat von Vault PKI generieren
.\scripts\generate-certs-vault.ps1 -Domain "loki.local"

# Services neu starten
docker compose up -d
```

Zugriff:
- **Web UI:** Über Grafana Explore (https://grafana.local:8443) - Loki hat keine eigene Web UI
- **API (Ready Check):** `curl -k "https://loki.local:8443/ready"` (Hinweis: Während der ersten ~15s nach Start zeigt Loki "Ingester not ready" - das ist normal)
- **API (Query):** `curl -k "https://loki.local:8443/loki/api/v1/query_range" --data-urlencode 'query={job="varlogs"}'`

**Alternative (interne Abfrage für Legacy-Zwecke):**
```bash
# Logs via direkter Loki Query (nicht über Traefik Gateway):
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="prometheus"}' | jq .
```

### Tempo Traces

Tempo ist über HTTPS via den Traefik **Gateway** verfügbar (Router `tempo` in `config/traefik/dynamic.yml`):

📚 **[TEMPO_VAULT_HTTPS.md](./tempo/TEMPO_VAULT_HTTPS.md)** - Vollständige Anleitung zur HTTPS-Konfiguration

Quick Start:
```powershell
# Zertifikat von Vault PKI generieren
.\scripts\generate-certs-vault.ps1 -Domain "tempo.local"

# Services neu starten
docker compose up -d
```

Zugriff:
- **Web UI:** https://tempo.local:8443 (Status/Metriken - für vollständige UI nutze Grafana Explore)
- **Via Grafana:** https://grafana.local:8443 → Explore → Tempo
- **OTLP Receivers (für Apps - TLS-gesichert):** 
  - gRPC: `https://localhost:4317` oder `https://tempo:4317` (intern)
  - HTTP: `https://localhost:4318` oder `https://tempo:4318` (intern)
  - **Wichtig:** Apps müssen Root CA vertrauen (siehe TEMPO_VAULT_HTTPS.md)

## 🛑 Services stoppen / neustarten

```bash
# Alle Services stoppen
docker compose down

# Alle Services stoppen und Volumes löschen (ACHTUNG!)
docker compose down -v

# Einen Service neu starten
docker compose restart grafana

# Services in den Logs folgen
docker compose logs -f keycloak
```

## � Deployment auf NAS

Wenn du die Services auf deinem NAS (statt localhost) betreiben möchtest:

### 1. Hostname in .env konfigurieren

```env
# Ersetze localhost mit deinem NAS Hostname/IP
HOST_NAME=nas.local
# oder
HOST_NAME=192.168.1.100
# oder
HOST_NAME=mynas.example.com
```

### 2. Gateway-Routing für NAS-Hostname anpassen

Da der Traefik **Gateway** die Routen aus `config/traefik/dynamic.yml` liest (keine Docker-Labels),
musst du dort die `vault`-Routing-Regel um deinen NAS-Hostnamen erweitern:

```yaml
# config/traefik/dynamic.yml – vault router (vor der Änderung):
vault:
  rule: "Host(`vault.local`) || Host(`localhost`)"

# Nach der Änderung mit NAS-Hostname nas.local:
vault:
  rule: "Host(`vault.local`) || Host(`localhost`) || Host(`nas.local`)"
```

Ersetze `nas.local` durch deinen tatsächlichen `HOST_NAME`-Wert.

### 3. Services nach Hostname-Änderung neu starten

```bash
# Stoppe alle Services
docker compose down

# Starte Services neu
docker compose up -d
```

### 4. Zugriff auf Services

- **Keycloak**: `https://keycloak.local:8443/admin` (via Traefik Gateway HTTPS)
- **Grafana**: `https://grafana.local:8443` (via Traefik Gateway HTTPS)
- **Prometheus**: `https://prometheus.local:8443` (via Traefik Gateway HTTPS)
- **Loki**: `https://loki.local:8443` (via Traefik Gateway HTTPS)
- **Tempo**: `https://tempo.local:8443` (via Traefik Gateway HTTPS)
- **RabbitMQ**: `https://rabbit.local:15671`
- **Vault**: `http://<HOST_NAME>:8201`

### 5. Keycloak Redirect URIs anpassen

In Keycloak Admin Console → Clients → dein Client:

- **Valid Redirect URIs**: `http://<HOST_NAME>:YOUR_APP_PORT/*`
- **Web Origins**: `http://<HOST_NAME>:YOUR_APP_PORT`

### 6. ASP.NET Core Apps anpassen

In deinen App-Konfigurationen:

```json
{
  "Keycloak": {
    "Authority": "https://keycloak.local:8443/realms/myapp",
    ...
  }
}
```

### 7. Firewall / Netzwerk

Stelle sicher, dass folgende Ports auf deinem NAS erreichbar sind:
- 8443 (Traefik Gateway HTTPS - für alle Services inkl. Keycloak, Grafana, Prometheus, Loki, Tempo)
- 8201 (Vault) für direkte PKI-Script-Zugriffe
- 15671 (RabbitMQ UI HTTPS)
- 5671 (RabbitMQ AMQPS) für App-Zugriff
- 4317, 4318 (Tempo OTLP Receivers) für Trace-Ingestion

## �🔧 Troubleshooting

### Services starten nicht

```bash
# Logs checken
docker compose logs <service-name>

# Vollständigen Rebuild versuchen
docker compose down -v
docker compose up -d --build
```

### Ports bereits in Verwendung

Ändere die Ports in `docker-compose.yml`:

```yaml
ports:
  - "8444:443"  # Traefik Gateway auf Port 8444 statt 8443
```

### Vault lädt nicht

```bash
# Vault Health Check
curl http://localhost:8201/v1/sys/health

# Mit Token initialisieren
docker compose exec vault vault operator init -key-shares=1 -key-threshold=1
```

## 📦 Integration mit ASP.NET Core

### 0. Keycloak Authentication (OpenID Connect)

```bash
dotnet add package Microsoft.AspNetCore.Authentication.OpenIdConnect
```

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = "Cookies";
    options.DefaultChallengeScheme = "oidc";
})
.AddCookie("Cookies")
.AddOpenIdConnect("oidc", options =>
{
    options.Authority = "http://keycloak:8080/realms/myapp";
    options.ClientId = "myapp-api";
    options.ClientSecret = builder.Configuration["Keycloak:ClientSecret"];
    options.ResponseType = "code";
    options.SaveTokens = true;
    options.Scope.Add("openid");
    options.Scope.Add("profile");
});

builder.Services.AddAuthorization();
var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.Run();
```

Siehe [KEYCLOAK_SETUP.md](./keycloak/KEYCLOAK_SETUP.md) für detaillierte Setup-Anweisungen.

### 1. OpenTelemetry hinzufügen

```bash
dotnet add package OpenTelemetry
dotnet add package OpenTelemetry.Exporter.Otlp
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
```

### 2. Konfiguration in Program.cs

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter(opt => 
        {
            opt.Endpoint = new Uri("https://localhost:4317");
            // Für Development: Self-signed Cert akzeptieren
            // Für Production: Root CA vertrauen (siehe TEMPO_VAULT_HTTPS.md)
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddPrometheusExporter());

var app = builder.Build();
app.MapPrometheusScrapingEndpoint();
app.Run();
```

### 3. RabbitMQ in ASP.NET Core

```bash
dotnet add package RabbitMQ.Client
```

```csharp
var factory = new ConnectionFactory() { HostName = "localhost" };
using var connection = factory.CreateConnection();
```

### 4. Vault Integration

```bash
dotnet add package VaultSharp
```

```csharp
var vaultClient = new VaultClient(new VaultClientSettings("http://localhost:8201/", auth));
var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path: "myapp");
```

## 📚 Weitere Ressourcen

- [Keycloak Setup & Administration](./keycloak/KEYCLOAK_SETUP.md)
- [Grafana Dokumentation](https://grafana.com/docs/)
- [RabbitMQ Dokumentation](https://www.rabbitmq.com/documentation.html)
- [Vault Documentation](https://www.vaultproject.io/docs)
- [Step CA / Zertifikatsverwaltung](PKI_SETUP.md)
- [OpenTelemetry für .NET](https://opentelemetry.io/docs/instrumentation/net/)
- [Keycloak Official Docs](https://www.keycloak.org/documentation)
- [OpenID Connect Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [Zertifikat Management Scripts](./scripts/README.md)

## 🔧 Schnelle Start-Befehle

```bash
# Alle Services starten
docker compose up -d

# Status überprüfen
docker compose ps

# Zertifikat generieren
./scripts/generate-certs.sh myapp.local

# Logs folgen
docker compose logs -f

# Services neustarten
docker compose down
docker compose up -d
```

## 📄 Lizenz

Dieses Setup nutzt Open-Source Komponenten mit verschiedenen Lizenzen (Apache 2.0, Mozilla Public License 2.0, etc.).
