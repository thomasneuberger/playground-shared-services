# Shared Services - Docker Compose Setup

Ein vollständiges Docker Compose Setup mit Open-Source Komponenten für ein Shared Services System.

## 🚀 Komponenten

- **Keycloak** (Port 8080) - OpenID Connect / OAuth2 / SAML Authentifizierung
- **RabbitMQ** (5672, 15672) - Message Queue mit Management UI
- **Vault** (8200) - Secret Store für Geheimnisse
- **Step CA** (9000) - Private Key Infrastructure für SSL/TLS Zertifikate
- **Prometheus** (9090) - Metriken-Erfassung
- **Loki** (3100) - Log-Aggregation
- **Tempo** (3200) - Distributed Tracing (OpenTelemetry)
- **Grafana** (3000) - Observability Dashboard
- **PostgreSQL** - Datenbank für Keycloak

## 📋 Voraussetzungen

- Docker Desktop oder Docker Engine (Windows/Linux/Mac)
- Docker Compose (v1.29+)
- Mindestens 4GB freier RAM für alle Services

## 🔧 Setup

### 1. Konfiguration anpassen

Öffne die `.env` Datei und ändere die Passwörter (Standard-Werte sind bereits konfiguriert):

```env
# Keycloak (Identity Management)
KEYCLOAK_DB_PASSWORD=Change_Me_Keycloak_123!
KEYCLOAK_ADMIN_PASSWORD=Change_Me_Admin_456!

# RabbitMQ (Message Broker)
RABBITMQ_PASSWORD=secure_rabbit_password

# Vault (Secret Store)
VAULT_TOKEN=secure_vault_token

# Grafana (Monitoring Dashboard)
GRAFANA_PASSWORD=Change_Me_Grafana_789!

# Step CA (Certificate Authority)
STEP_CA_PASSWORD=Change_Me_StepCA_012!
```

### 2. Services starten

```bash
# Alle Services im Hintergrund starten
docker-compose up -d

# Logs anschauen
docker-compose logs -f

# Spezifische Logs
docker-compose logs -f grafana
```

### 3. Services überprüfen

```bash
# Status aller Services
docker-compose ps

# Health Check
docker-compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"
```

## 🌐 Zugriff auf Services

| Service | URL | Credentials |
|---------|-----|-------------|
| **Keycloak** | http://localhost:8080 | admin / (siehe .env) |
| **Grafana** | http://localhost:3000 | admin / (siehe .env) |
| **Prometheus** | http://localhost:9090 | - |
| **RabbitMQ UI** | http://localhost:15672 | guest / guest |
| **Vault** | http://localhost:8200 | Token: (siehe .env) |
| **Step CA** | http://localhost:9000 | - |
| **Loki** | http://localhost:3100 | - |
| **Tempo** | http://localhost:3200 | - |

## 📊 Grafana Setup (beim ersten Start)

1. Öffne http://localhost:3000
2. Login mit Admin-Benutzer
3. Datasources sind bereits vorbereitet:
   - Prometheus (Metriken)
   - Loki (Logs)
   - Tempo (Traces)
4. Erstelle ein Dashboard oder führe Queries aus

## 🔐 Vault Setup (Initial)

```bash
# In den Vault Container gehen
docker-compose exec vault sh

# Root Token verwenden (aus .env)
export VAULT_TOKEN=myroot123

# Secrets erstellen
vault kv put secret/myapp/database \
  username=dbuser \
  password=dbpass

# Secrets lesen
vault kv get secret/myapp/database
```
## 🔐 Keycloak Setup (Initial)

Keycloak wird automatisch initialisiert. Admin-Zugriff:

```bash
# 1. Öffne Keycloak Admin Console
# http://localhost:8080/admin

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
```

# 5. OpenID Discovery Endpoint
# http://localhost:8080/realms/myapp/.well-known/openid-configuration
```
## � Step CA (PKI) Setup

Step CA wird automatisch beim Start initialisiert. Für Zertifikatsverwaltung:

```bash
# Step CLI installieren: https://smallstep.com/docs/step-cli/installation/

# Zertifikat generieren
step ca certificate \
  --ca-url http://localhost:9000 \
  --root ./certs/root_ca.crt \
  --insecure \
  localhost localhost.crt localhost.key

# Zertifikat Details anschauen
step certificate inspect ./localhost.crt
```

**Wichtig**: Root CA im System Trust Store registrieren (siehe [PKI_SETUP.md](PKI_SETUP.md))

## �📨 RabbitMQ Setup

1. Öffne http://localhost:15672
2. Login: guest / guest
3. Queues und Topics erstellen unter dem Punkt "Queues"

## 📝 Logs und Monitoring

### Prometheus Metrics sammeln

```bash
# Prometheus selbst monitoren
curl http://localhost:9090/api/v1/query?query=up
```

### Loki Logs durchsuchen

```bash
# Logs via Grafana Explorer oder direkter Loki Query:
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="prometheus"}' | jq .
```

### Tempo Traces

Über Grafana → Explore → Tempo

## 🛑 Services stoppen / neustarten

```bash
# Alle Services stoppen
docker-compose down

# Alle Services stoppen und Volumes löschen (ACHTUNG!)
docker-compose down -v

# Einen Service neu starten
docker-compose restart grafana

# Services in den Logs folgen
docker-compose logs -f keycloak
```

## 🔧 Troubleshooting

### Services starten nicht

```bash
# Logs checken
docker-compose logs <service-name>

# Vollständigen Rebuild versuchen
docker-compose down -v
docker-compose up -d --build
```

### Ports bereits in Verwendung

Ändere die Ports in `docker-compose.yml`:

```yaml
ports:
  - "3001:3000"  # Grafana auf Port 3001 statt 3000
```

### Vault lädt nicht

```bash
# Vault Health Check
curl http://localhost:8200/v1/sys/health

# Mit Token initialisieren
docker-compose exec vault vault operator init -key-shares=1 -key-threshold=1
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

Siehe [KEYCLOAK_SETUP.md](KEYCLOAK_SETUP.md) für detaillierte Setup-Anweisungen.

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
            opt.Endpoint = new Uri("http://localhost:4317");
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
var vaultClient = new VaultClient(new VaultClientSettings("http://localhost:8200/", auth));
var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path: "myapp");
```

## 📚 Weitere Ressourcen

- [Keycloak Setup & Administration](KEYCLOAK_SETUP.md)
- [Grafana Dokumentation](https://grafana.com/docs/)
- [RabbitMQ Dokumentation](https://www.rabbitmq.com/documentation.html)
- [Vault Documentation](https://www.vaultproject.io/docs)
- [Step CA / Zertifikatsverwaltung](PKI_SETUP.md)
- [OpenTelemetry für .NET](https://opentelemetry.io/docs/instrumentation/net/)
- [Keycloak Official Docs](https://www.keycloak.org/documentation)
- [OpenID Connect Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [Zertifikat Management Scripts](scripts/README.md)

## 🔧 Schnelle Start-Befehle

```bash
# Alle Services starten
docker-compose up -d

# Status überprüfen
docker-compose ps

# Zertifikat generieren
./scripts/generate-certs.sh myapp.local

# Logs folgen
docker-compose logs -f

# Services neustarten
docker-compose down
docker-compose up -d
```

## 📄 Lizenz

Dieses Setup nutzt Open-Source Komponenten mit verschiedenen Lizenzen (Apache 2.0, Mozilla Public License 2.0, etc.).
