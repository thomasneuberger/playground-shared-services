# 🔐 Tempo HTTPS with Vault PKI Certificate (Traefik TLS Termination)

Configure Tempo to use HTTPS via Traefik, with certificates from the Vault PKI Engine.

**Architecture:**
- Tempo Web UI/API runs internally on port 3200 (not exposed externally)
- Traefik handles TLS termination with Vault PKI certificates for Web UI
- HTTPS-only access through Traefik for Web UI/API
- **OTLP receiver ports (4317 gRPC, 4318 HTTP) use TLS with Vault PKI certificates**
- Applications must use TLS when sending traces to OTLP receivers
- Clean separation of concerns (Tempo doesn't manage certificates)

## Overview

This guide shows how to:
1. Generate a server certificate for Tempo from Vault PKI
2. Configure Traefik to route HTTPS traffic to Tempo's Web UI/API
3. Access Tempo securely via HTTPS

## Prerequisites

- Vault PKI Engine initialized and running
- Vault CLI tool installed
- Docker and Docker Compose

### Installation

**Windows:**
```powershell
choco install vault
```

**Linux/macOS:**
```bash
# Ubuntu/Debian
sudo apt-get install vault

# macOS
brew install hashicorp/tap/vault
```

## Quick Start

### Step 1: Generate Certificate

Run the generate-certs script to create a Tempo certificate from Vault PKI:

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "tempo.local"

# Or with custom domain and IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "tempo.example.com" -IpSans "192.168.1.10"
```

**Linux/macOS:**
```bash
./scripts/generate-certs-vault.sh -d tempo.local
./scripts/generate-certs-vault.sh -d tempo.example.com -i 192.168.1.10
```

The script will:
- ✅ Generate certificate from Vault PKI
- ✅ Save `tempo.local.crt` and `tempo.local.key`
- ✅ Export Root CA as `root_ca.crt`
- ✅ Create additional files (ca-chain, bundle) for reference

### Step 2: Verify docker-compose.yml

Tempo is already configured with Traefik labels. Verify the following in `docker-compose.yml`:

```yaml
tempo:
  image: grafana/tempo:latest
  ports:
    - "4317:4317"     # OTLP gRPC receiver (TLS)
    - "4318:4318"     # OTLP HTTP receiver (TLS)
  volumes:
    - ./certs:/certs:ro  # Mount certificates for OTLP TLS
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.tempo.rule=Host(`tempo.local`)"
    - "traefik.http.routers.tempo.entrypoints=websecure"
    - "traefik.http.routers.tempo.tls=true"
    - "traefik.http.services.tempo.loadbalancer.server.port=3200"
```

**Note:** Port 3200 (Web UI) is not exposed externally. Ports 4317 and 4318 use TLS for secure trace ingestion.

### Step 3: Verify Traefik Configuration

Traefik is configured to use the Tempo certificate. Check `config/traefik/dynamic.yml`:

```yaml
http:
  routers:
    tempo:
      rule: "Host(`tempo.local`)"
      entryPoints:
        - websecure
      service: tempo-service
      tls: {}
  
  services:
    tempo-service:
      loadBalancer:
        servers:
          - url: "http://tempo:3200"

tls:
  certificates:
    - certFile: /certs/tempo.local.crt
      keyFile: /certs/tempo.local.key
```

This is already in place. No manual configuration needed!

### Step 4: Update /etc/hosts (Optional but Recommended)

To access Tempo via `https://tempo.local`, add an entry to your hosts file:

**Windows (as Administrator):**
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n127.0.0.1`ttempo.local"
```

Or edit `C:\Windows\System32\drivers\etc\hosts` directly:
```
127.0.0.1  tempo.local
```

**Linux/macOS:**
```bash
sudo sh -c 'echo "127.0.0.1  tempo.local" >> /etc/hosts'
```

### Step 5: Restart Services

```bash
docker compose up -d

# Wait for services to be ready
sleep 10

# Check logs
docker compose logs -f traefik tempo
```

### Step 6: Access Tempo via HTTPS

**Web UI (Status/Metrics):**
```
https://tempo.local:8443
```

**API Endpoints:**
```bash
# Health/Status
curl -k https://tempo.local:8443/api/echo

# Metrics
curl -k https://tempo.local:8443/metrics

# Search traces (if any exist)
curl -k https://tempo.local:8443/api/search
```

**Important:** Tempo's Web UI is minimal and primarily shows status/metrics. For a full UI experience, use **Grafana's Explore** feature.

### Step 7: Trust the Root CA (Optional)

Your browser may warn about the certificate. To trust it system-wide:

**Windows:**
```powershell
certutil -addstore -f "ROOT" "./certs/root_ca.crt"
```

**Linux:**
```bash
sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./certs/root_ca.crt
```

## Behind the Scenes

### Traefik Port Mapping

Traefik is configured with HTTPS entry point:
- **Port 8443 (external) → 443 (internal)**: Handles HTTPS traffic with TLS certificates

When you access `https://tempo.local:8443`:
1. Traefik receives the HTTPS request on port 8443 (mapped to internal port 443)
2. Matches the hostname `tempo.local` against the router rules
3. Loads the corresponding TLS certificate (`tempo.local.crt` + `tempo.local.key`)
4. Decrypts the request and proxies it to Tempo's internal port 3200

### Port Architecture

**HTTPS via Traefik (Web UI/API):**
- Port 3200 (internal only) → Accessible via `https://tempo.local:8443`

**TLS-secured OTLP Receivers (for applications):**
- Port 4317 (gRPC with TLS) → `https://localhost:4317` or `tempo:4317` (internal)
- Port 4318 (HTTP with TLS) → `https://localhost:4318` or `tempo:4318` (internal)

Applications send traces to the TLS-secured OTLP receivers, while humans access the Web UI via HTTPS through Traefik.

**Important:** Applications must be configured to:
1. Use `https://` scheme (not `http://`)
2. Trust the Root CA certificate or disable certificate verification (development only)

### Certificate Locations

Certificates are stored in the `./certs/` directory:
- `tempo.local.crt` - Server certificate
- `tempo.local.key` - Private key
- `root_ca.crt` - Root CA certificate (trust this in your OS)
- `ca_chain.crt` - Full certificate chain

### HTTPS-Only Security for Web UI and TLS for OTLP

Tempo's Web UI/API is configured for HTTPS-only access via Traefik. Additionally, **OTLP receivers are secured with TLS** using the same Vault PKI certificates. This provides:
- ✅ Mandatory encryption for all web connections
- ✅ No plaintext HTTP exposure for Web UI
- ✅ **TLS encryption for trace ingestion (OTLP ports 4317, 4318)**
- ✅ End-to-end encryption from application to storage
- ✅ Centralized certificate management via Vault PKI

If you need to disable TLS on OTLP receivers for development, edit `config/tempo-config.yml` and remove the TLS sections:

```yaml
distributor:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
          # Remove tls section
        http:
          endpoint: 0.0.0.0:4318
          # Remove tls section
```

Then restart Tempo:
```bash
docker compose restart tempo
```

## Troubleshooting

### Certificate not found

If you see errors like "certificate not found", ensure:
1. Certificate files exist: `./certs/tempo.local.crt` and `./certs/tempo.local.key`
2. Traefik can read the files (check permissions)
3. Paths in `dynamic.yml` are correct

```bash
ls -la ./certs/tempo.local.*
```

### Traefik not routing to Tempo

Check Traefik logs:
```bash
docker compose logs -f traefik
```

Verify the router rule matches your domain:
```bash
# Should show status or metrics
curl -k -H "Host: tempo.local" https://127.0.0.1:8443/api/echo
curl -k -H "Host: tempo.local" https://127.0.0.1:8443/metrics
```

### Browser untrusted certificate warning

This is expected if the Root CA is not trusted by your OS. Either:
1. Import the Root CA (`./certs/root_ca.crt`) into your system trust store
2. Add an exception in your browser (development only)

### Grafana unable to reach Tempo

If Grafana cannot query Tempo:
- Ensure all services are on the same Docker network (`shared-services`)
- Use service names (e.g., `http://tempo:3200`) not localhost in Grafana datasource config
- Check network connectivity: `docker compose exec grafana wget -qO- http://tempo:3200/api/echo`

### Applications can't send traces to OTLP receivers

If applications cannot send traces:
- **Verify TLS configuration:** Applications must use `https://` (not `http://`) for OTLP endpoints
- **Trust the Root CA:** Applications need to trust the Vault Root CA certificate
- **Check ports:** Verify ports 4317 (gRPC) and 4318 (HTTP) are accessible
- **Test connectivity:**
  ```bash
  # Test gRPC endpoint (should show TLS handshake)
  openssl s_client -connect localhost:4317
  
  # Test HTTP endpoint
  curl -k https://localhost:4318/v1/traces
  ```
- **Check Tempo logs:** `docker compose logs tempo`
- **Development workaround:** Temporarily disable certificate verification (not for production):

## Customization

### Using a Custom Domain

If you use a different domain (e.g., `tempo.example.com`):

```powershell
# Generate certificate for custom domain
.\scripts\generate-certs-vault.ps1 -Domain "tempo.example.com"
```

Update `docker-compose.yml`:
```yaml
labels:
  - "traefik.http.routers.tempo.rule=Host(`tempo.example.com`)"
```

Update `config/traefik/dynamic.yml`:
```yaml
routers:
  tempo:
    rule: "Host(`tempo.example.com`)"

tls:
  certificates:
    - certFile: /certs/tempo.example.com.crt
      keyFile: /certs/tempo.example.com.key
```

Update your hosts file or DNS records:
```
127.0.0.1  tempo.example.com
```

## Integration with Services

### Viewing Traces

**Via Grafana (Recommended):**
1. Open `https://grafana.local:8443`
2. Go to **Explore** (compass icon)
3. Select **Tempo** as the datasource
4. Search for traces by:
   - Trace ID
   - Service name
   - Time range

**Via API (through Traefik):**
```bash
# Search traces
curl -k "https://tempo.local:8443/api/search?tags=service.name%3Dmyapp"

# Get trace by ID
curl -k "https://tempo.local:8443/api/traces/<trace-id>"
```

**Internal (from Grafana datasource):**
Grafana connects to Tempo internally:
```yaml
datasources:
  - name: Tempo
    type: tempo
    url: http://tempo:3200
```

### Sending Traces to Tempo

Applications should send traces to Tempo's TLS-secured OTLP receivers:

**gRPC with TLS (recommended):**
```
https://tempo:4317
# or from host
https://localhost:4317
```

**HTTP with TLS:**
```
https://tempo:4318
# or from host
https://localhost:4318
```

**Example with OpenTelemetry (C#):**
```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter(opt => 
        {
            opt.Endpoint = new Uri("https://tempo:4317");
            opt.Protocol = OtlpExportProtocol.Grpc;
            
            // For development: trust self-signed certificates
            opt.HttpClientFactory = () =>
            {
                var handler = new HttpClientHandler();
                handler.ServerCertificateCustomValidationCallback =
                    HttpClientHandler.DangerousAcceptAnyServerCertificateValidator;
                return new HttpClient(handler);
            };
            
            // For production: trust the Root CA certificate
            // Add root_ca.crt to your application's trusted certificates
        }));
```

**Trusting the Root CA in Applications:**

For production, applications should trust the Vault Root CA:

```csharp
// Load and trust the Root CA certificate
var rootCA = new X509Certificate2("path/to/root_ca.crt");
using var store = new X509Store(StoreName.Root, StoreLocation.CurrentUser);
store.Open(OpenFlags.ReadWrite);
store.Add(rootCA);
store.Close();
```

## References

- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Traefik Documentation](https://doc.traefik.io/)
- [Vault PKI Documentation](https://www.vaultproject.io/docs/secrets/pki)
- [OpenTelemetry Protocol (OTLP)](https://opentelemetry.io/docs/specs/otlp/)
- [Tempo TraceQL Query Language](https://grafana.com/docs/tempo/latest/traceql/)
