# 🔐 Grafana HTTPS with Vault PKI Certificate (Traefik TLS Termination)

Configure Grafana to use HTTPS via Traefik, with certificates from the Vault PKI Engine.

**Architecture:**
- Grafana runs internally on port 3000 (not exposed externally)
- Traefik handles TLS termination with Vault PKI certificates
- HTTPS-only access through Traefik
- Clean separation of concerns (Grafana doesn't manage certificates)

## Overview

This guide shows how to:
1. Generate a server certificate for Grafana from Vault PKI
2. Configure Traefik to route HTTPS traffic to Grafana
3. Access Grafana securely via HTTPS

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

Run the generate-certs script to create a Grafana certificate from Vault PKI:

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "grafana.local"

# Or with custom domain and IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "grafana.example.com" -IpSans "192.168.1.10"
```

**Linux/macOS:**
```bash
./scripts/generate-certs-vault.sh -d grafana.local
./scripts/generate-certs-vault.sh -d grafana.example.com -i 192.168.1.10
```

The script will:
- ✅ Generate certificate from Vault PKI
- ✅ Save `grafana.local.crt` and `grafana.local.key`
- ✅ Export Root CA as `root_ca.crt`
- ✅ Create additional files (ca-chain, bundle) for reference

### Step 2: Verify docker-compose.yml

Grafana is already configured with Traefik labels. Verify the following in `docker-compose.yml`:

```yaml
grafana:
  image: grafana/grafana:latest
  environment:
    GF_SECURITY_ADMIN_USER: ${GRAFANA_USER:-admin}
    GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.grafana.rule=Host(`grafana.local`)"
    - "traefik.http.routers.grafana.entrypoints=websecure"
    - "traefik.http.routers.grafana.tls=true"
    - "traefik.http.services.grafana.loadbalancer.server.port=3000"
```

### Step 3: Verify Traefik Configuration

Traefik is configured to use the Grafana certificate. Check `config/traefik/dynamic.yml`:

```yaml
http:
  routers:
    grafana:
      rule: "Host(`grafana.local`)"
      entryPoints:
        - websecure
      service: grafana-service
      tls: {}
  
  services:
    grafana-service:
      loadBalancer:
        servers:
          - url: "http://grafana:3000"

tls:
  certificates:
    - certFile: /certs/grafana.local.crt
      keyFile: /certs/grafana.local.key
```

This is already in place. No manual configuration needed!

### Step 4: Update /etc/hosts (Optional but Recommended)

To access Grafana via `https://grafana.local`, add an entry to your hosts file:

**Windows (as Administrator):**
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n127.0.0.1`tgrafana.local"
```

Or edit `C:\Windows\System32\drivers\etc\hosts` directly:
```
127.0.0.1  grafana.local
```

**Linux/macOS:**
```bash
sudo sh -c 'echo "127.0.0.1  grafana.local" >> /etc/hosts'
```

### Step 5: Restart Services

```bash
docker compose up -d

# Wait for services to be ready
sleep 10

# Check logs
docker compose logs -f traefik grafana
```

### Step 6: Access Grafana via HTTPS

```
https://grafana.local:8443
```

**Important:** Grafana is **only** accessible via HTTPS through Traefik. Direct HTTP access is not available.

**Login with:**
- Username: `admin` (default from `GF_SECURITY_ADMIN_USER`)
- Password: (check `.env:GRAFANA_PASSWORD` or use default `admin`)

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

When you access `https://grafana.local:8443`:
1. Traefik receives the HTTPS request on port 8443 (mapped to internal port 443)
2. Matches the hostname `grafana.local` against the router rules
3. Loads the corresponding TLS certificate (`grafana.local.crt` + `grafana.local.key`)
4. Decrypts the request and proxies it to Grafana's internal port 3000

### Certificate Locations

Certificates are stored in the `./certs/` directory:
- `grafana.local.crt` - Server certificate
- `grafana.local.key` - Private key
- `root_ca.crt` - Root CA certificate (trust this in your OS)
- `ca_chain.crt` - Full certificate chain

### HTTPS-Only Security

Grafana is configured for HTTPS-only access. The HTTP port (3000) is not exposed externally, ensuring all traffic goes through Traefik's secure HTTPS endpoint. This provides:
- ✅ Mandatory encryption for all connections
- ✅ No plaintext HTTP exposure
- ✅ Centralized certificate management via Traefik

If you need to expose HTTP for development purposes, add a port mapping in `docker-compose.yml`:

```yaml
grafana:
  ports:
    - "3000:3000"  # HTTP access (not recommended for production)
```

Then restart Grafana:
```bash
docker compose restart grafana
```

## Troubleshooting

### Certificate not found

If you see errors like "certificate not found", ensure:
1. Certificate files exist: `./certs/grafana.local.crt` and `./certs/grafana.local.key`
2. Traefik can read the files (check permissions)
3. Paths in `dynamic.yml` are correct

```bash
ls -la ./certs/grafana.local.*
```

### Traefik not routing to Grafana

Check Traefik logs:
```bash
docker compose logs -f traefik
```

Verify the router rule matches your domain:
```bash
# Should show 200 OK
curl -k -H "Host: grafana.local" https://127.0.0.1
```

### Browser untrusted certificate warning

This is expected if the Root CA is not trusted by your OS. Either:
1. Import the Root CA (`./certs/root_ca.crt`) into your system trust store
2. Add an exception in your browser (development only)

### Grafana unable to reach services

If Grafana cannot resolve Loki, Prometheus, or Tempo:
- Ensure all services are on the same Docker network (`shared-services`)
- Use service names (e.g., `http://prometheus:9090`) not localhost
- Check network connectivity: `docker compose exec grafana ping prometheus`

## Customization

### Using a Custom Domain

If you use a different domain (e.g., `grafana.example.com`):

```powershell
# Generate certificate for custom domain
.\scripts\generate-certs-vault.ps1 -Domain "grafana.example.com"
```

Update `docker-compose.yml`:
```yaml
labels:
  - "traefik.http.routers.grafana.rule=Host(`grafana.example.com`)"
```

Update `config/traefik/dynamic.yml`:
```yaml
routers:
  grafana:
    rule: "Host(`grafana.example.com`)"

tls:
  certificates:
    - certFile: /certs/grafana.example.com.crt
      keyFile: /certs/grafana.example.com.key
```

Update your hosts file or DNS records:
```
127.0.0.1  grafana.example.com
```

## Integration with Services

Grafana is already configured to connect to observability services:
- **Prometheus** - Metrics (http://prometheus:9090)
- **Loki** - Logs (http://loki:3100)
- **Tempo** - Traces (http://tempo:3200)

These datasources are pre-provisioned in `config/grafana/provisioning/datasources/`.

Access them securely via HTTPS through Traefik while they communicate internally via HTTP.

## References

- [Grafana Documentation](https://grafana.com/docs/)
- [Traefik Documentation](https://doc.traefik.io/)
- [Vault PKI Documentation](https://www.vaultproject.io/docs/secrets/pki)
- [OpenTelemetry Integration](https://grafana.com/docs/grafana/latest/datasources/)
