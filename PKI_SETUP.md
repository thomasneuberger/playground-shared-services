# 🔐 Zertifikatsinfrastruktur (PKI) mit Step CA

Dieses Setup integriert **Step CA** (Smallstep Certificates) als Private Key Infrastructure für SSL/TLS und Client-Zertifikate.

## 🌟 Komponenten

- **Step CA** (Port 9000) - Certificate Authority für Zertifikatverwaltung
- **Root CA** - Root Certificate Authority (selfsigned)
- **Intermediate CA** - Intermediate CA für die Ausstellung von Zertifikaten
- **ACME Support** - Automatische Zertifikatsverwaltung

## 🚀 Schnelleinstieg

### 1. Passwörter anpassen (optional)

```bash
# .env Datei anpassen
STEP_CA_PASSWORD=MeinSicheresPasswort!
STEP_CA_PROVISIONER_PASSWORD=ProvisionalPassword!
```

### 2. Step CA starten

```bash
docker-compose up -d step-ca

# Logs checken
docker-compose logs -f step-ca
```

### 3. Health Check

```bash
# Von außerhalb des Containers
docker-compose exec step-ca sh

# Im Container
step ca health --insecure
```

## 📦 Zertifikate generieren

### Option 1: Über `step` CLI (Lokal)

```bash
# Step CLI installieren (https://smallstep.com/docs/step-cli/installation/)

# Zertifikat für localhost
step ca certificate \
  --ca-url http://localhost:9000 \
  --root /path/to/root_ca.crt \
  --insecure \
  localhost localhost.crt localhost.key

# Zertifikat für Domainnamen
step ca certificate \
  --ca-url http://localhost:9000 \
  --san myapp.local \
  --san api.myapp.local \
  --root /path/to/root_ca.crt \
  --insecure \
  myapp \
  myapp.crt \
  myapp.key
```

### Option 2: Über Container

```bash
# In den Step CA Container gehen
docker-compose exec step-ca sh

# Zertifikat generieren
step ca certificate \
  localhost localhost.crt localhost.key

# Zertifikat exportieren
docker cp shared-step-ca:/home/step/localhost.crt ./certs/
docker cp shared-step-ca:/home/step/localhost.key ./certs/
```

### Option 3: Batch-Zertifikate erstellen

```bash
#!/bin/bash
DOMAINS=("myapp.local" "api.myapp.local" "auth.myapp.local")

for domain in "${DOMAINS[@]}"; do
  step ca certificate \
    --ca-url http://localhost:9000 \
    --san "$domain" \
    --root /path/to/root_ca.crt \
    --insecure \
    "$domain" \
    "certs/$domain.crt" \
    "certs/$domain.key"
done
```

## 🔒 Client Zertifikate (mTLS)

### 1. Client-Zertifikat erstellen

```bash
# Client Zertifikat
step ca certificate \
  --ca-url http://localhost:9000 \
  --client \
  --profile leaf \
  --root /path/to/root_ca.crt \
  --insecure \
  client@example.com \
  client.crt \
  client.key
```

### 2. Root CA exportieren

```bash
# Damit Clients den Server verifizieren können
docker cp shared-step-ca:/home/step/certs/root_ca.crt ./certs/root_ca.crt

# PEM Format überprüfen
docker-compose exec step-ca step certificate inspect --format json root_ca.crt
```

## 🔑 Private CA Root in den System Trust Store laden

### Windows

```powershell
# Root CA ins Windows Certificate Store importieren
Import-Certificate -FilePath ".\certs\root_ca.crt" `
  -CertStoreLocation "Cert:\LocalMachine\Root"

# Überprüfen
Get-ChildItem -Path "Cert:\LocalMachine\Root" | Where-Object { $_.Subject -like "*SharedServices*" }
```

### Linux

```bash
# Ubuntu/Debian
sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Fedora/RHEL
sudo cp ./certs/root_ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

### Mac

```bash
# Root CA zur Keychain hinzufügen
sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ./certs/root_ca.crt
```

## 🌐 HTTPS in Kubernetes/Docker Secrets verwenden

```bash
# Secret mit Zertifikat erstellen
docker secret create myapp.crt ./certs/myapp.crt
docker secret create myapp.key ./certs/myapp.key

# In docker-compose.yml referenzieren
services:
  myapp:
    secrets:
      - source: myapp.crt
        target: /app/certs/server.crt
      - source: myapp.key
        target: /app/certs/server.key
    environment:
      ASPNETCORE_Kestrel__Certificates__Default__Path: /app/certs/server.crt
      ASPNETCORE_Kestrel__Certificates__Default__KeyPath: /app/certs/server.key
```

## 🔄 Zertifikat Rotation

```bash
#!/bin/bash
# Zertifikat erneuern
step ca renew ./certs/myapp.crt ./certs/myapp.key \
  --ca-url http://localhost:9000 \
  --root /path/to/root_ca.crt \
  --insecure

# Oder alternativ neue Zertifikate generieren
step ca certificate \
  --ca-url http://localhost:9000 \
  --root /path/to/root_ca.crt \
  --insecure \
  --force \
  myapp myapp.crt myapp.key
```

**Geplante Rotation in Cron:**

```bash
# Täglich um 2 Uhr morgens Zertifikat erneuern
0 2 * * * /opt/scripts/renew-cert.sh
```

## 🔍 Zertifikat Informationen anzeigen

```bash
# Zertifikat Details ansehen
step certificate inspect ./certs/myapp.crt --format json

# Ablaufdatum überprüfen
step certificate inspect ./certs/myapp.crt \
  | grep -i "notAfter\|valid"

# Key Details
step crypto key inspect ./certs/myapp.key
```

## 📊 Prometheus Monitoring

Step CA metriken unter `http://localhost:9000/metrics` verfügbar:

```yaml
# prometheus.yml hinzufügen
- job_name: 'step-ca'
  static_configs:
    - targets: ['step-ca:9000']
  metrics_path: '/metrics'
```

## 🔗 Integration mit ASP.NET Core

### HTTPS Server

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// Kestrel HTTPS konfigurieren
builder.WebHost.ConfigureKestrel((context, options) =>
{
    options.ListenAnyIP(5001, listenOptions =>
    {
        listenOptions.UseHttps(
            certificatePath: "/app/certs/server.crt",
            keyPath: "/app/certs/server.key"
        );
    });
});

var app = builder.Build();
app.Run();
```

### Client Authentifizierung (mTLS)

```csharp
// Services registrieren
builder.Services.AddHttpClient("mTLS")
    .ConfigureHttpClient(client =>
    {
        client.DefaultRequestHeaders.Add("User-Agent", "MyApp/1.0");
    })
    .ConfigureHttpMessageHandlerBuilder(builder =>
    {
        var clientCert = new X509Certificate2(
            "/app/certs/client.crt",
            "", // Falls verschlüsselt: Passwort
            X509KeyStorageFlags.PersistKeySet
        );
        
        var handler = new HttpClientHandler();
        handler.ClientCertificates.Add(clientCert);
        handler.ServerCertificateCustomValidationCallback = (msg, cert, chain, errors) =>
        {
            // Custom Validierung oder CA Chain Check
            return errors == System.Net.Security.SslPolicyErrors.None;
        };
        
        builder.PrimaryHandler = handler;
    });

var app = builder.Build();
app.Run();
```

### Server-Zertifikat Validierung in Services

```csharp
// Speichere Root CA
var rootCa = new X509Certificate2("/app/certs/root_ca.crt");

// HttpClientHandler mit Custom Trust Store
var handler = new HttpClientHandler();
var certStore = new X509Store(StoreName.Root, StoreLocation.CurrentUser);
certStore.Open(OpenFlags.ReadWrite);
certStore.Add(rootCa);

var httpClient = new HttpClient(handler)
{
    BaseAddress = new Uri("https://api.myapp.local:443")
};
```

## 🚨 Problembehebung

### Problem: "Unable to verify certificate chain"

```bash
# Root CA neu exportieren und ins System Trust einbinden
docker cp shared-step-ca:/home/step/certs/root_ca.crt ./
# Windows: Import-Certificate...
# Linux: sudo cp root_ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
```

### Problem: "Certificate CN validation failed"

```bash
# Überprüfe CN / SANs
step certificate inspect myapp.crt | grep -i "subject\|dns"

# Neu generieren mit korrekten SANs
step ca certificate --san myapp.local --san *.myapp.local ...
```

### Problem: Step CA startet nicht

```bash
# Logs anuschauen
docker-compose logs step-ca

# Container manuell starten
docker-compose exec step-ca /bin/sh

# STEPPATH überprüfen
ls -la /home/step/
```

## 📚 Best Practices

✅ **Regelmäßig rotieren** - Zertifikate nicht länger als 90 Tage verwenden
✅ **Passwörter sicher speichern** - .env in .gitignore, Vault nutzen
✅ **Root CA sicher verwahren** - Offline Backup machen
✅ **Monitoring aktivieren** - Ablaufdaten tracken
✅ **Client Zertifikate trennen** - Pro Service ein Zertifikat
✅ **CN/SAN korrekt setzen** - Verhindert Domain Validation Fehler

## 🔗 Weitere Ressourcen

- [Step CA Documentation](https://smallstep.com/docs/step-ca/)
- [Step CLI Reference](https://smallstep.com/docs/step-cli/)
- [ACME Protocol](https://tools.ietf.org/html/rfc8555)
- [mTLS Best Practices](https://smallstep.com/blog/mutually-authenticated-tls/)
