# 🔐 Prometheus HTTPS with Vault PKI Certificate (Traefik TLS Termination)

Configure Prometheus to use HTTPS via Traefik, with certificates from the Vault PKI Engine.

**Architecture:**
- Prometheus runs internally on port 9090 (not exposed externally)
- Traefik handles TLS termination with Vault PKI certificates
- HTTPS-only access through Traefik
- Clean separation of concerns (Prometheus doesn't manage certificates)

## Overview

This guide shows how to:
1. Generate a server certificate for Prometheus from Vault PKI
2. Configure Traefik to route HTTPS traffic to Prometheus
3. Access Prometheus securely via HTTPS

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

Run the generate-certs script to create a Prometheus certificate from Vault PKI:

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "prometheus.local"

# Or with custom domain and IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "prometheus.example.com" -IpSans "192.168.1.10"
```

**Linux/macOS:**
```bash
./scripts/generate-certs-vault.sh -d prometheus.local
./scripts/generate-certs-vault.sh -d prometheus.example.com -i 192.168.1.10
```

The script will:
- ✅ Generate certificate from Vault PKI
- ✅ Save `prometheus.local.crt` and `prometheus.local.key`
- ✅ Export Root CA as `root_ca.crt`
- ✅ Create additional files (ca-chain, bundle) for reference

### Step 2: Verify docker-compose.yml

Prometheus is already configured with Traefik labels. Verify the following in `docker-compose.yml`:

```yaml
prometheus:
  image: prom/prometheus:latest
  environment:
    # ... Prometheus configuration
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.prometheus.rule=Host(`prometheus.local`)"
    - "traefik.http.routers.prometheus.entrypoints=websecure"
    - "traefik.http.routers.prometheus.tls=true"
    - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
```

### Step 3: Verify Traefik Configuration

Traefik is configured to use the Prometheus certificate. Check `config/traefik/dynamic.yml`:

```yaml
http:
  routers:
    prometheus:
      rule: "Host(`prometheus.local`)"
      entryPoints:
        - websecure
      service: prometheus-service
      tls: {}
  
  services:
    prometheus-service:
      loadBalancer:
        servers:
          - url: "http://prometheus:9090"

tls:
  certificates:
    - certFile: /certs/prometheus.local.crt
      keyFile: /certs/prometheus.local.key
```

This is already in place. No manual configuration needed!

### Step 4: Update /etc/hosts (Optional but Recommended)

To access Prometheus via `https://prometheus.local`, add an entry to your hosts file:

**Windows (as Administrator):**
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n127.0.0.1`tprometheus.local"
```

Or edit `C:\Windows\System32\drivers\etc\hosts` directly:
```
127.0.0.1  prometheus.local
```

**Linux/macOS:**
```bash
sudo sh -c 'echo "127.0.0.1  prometheus.local" >> /etc/hosts'
```

### Step 5: Restart Services

```bash
docker compose up -d

# Wait for services to be ready
sleep 10

# Check logs
docker compose logs -f traefik prometheus
```

### Step 6: Access Prometheus via HTTPS

```
https://prometheus.local:8443
```

**Important:** Prometheus is **only** accessible via HTTPS through Traefik. Direct HTTP access is not available.

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

When you access `https://prometheus.local:8443`:
1. Traefik receives the HTTPS request on port 8443 (mapped to internal port 443)
2. Matches the hostname `prometheus.local` against the router rules
3. Loads the corresponding TLS certificate (`prometheus.local.crt` + `prometheus.local.key`)
4. Decrypts the request and proxies it to Prometheus's internal port 9090

### Certificate Locations

Certificates are stored in the `./certs/` directory:
- `prometheus.local.crt` - Server certificate
- `prometheus.local.key` - Private key
- `root_ca.crt` - Root CA certificate (trust this in your OS)
- `ca_chain.crt` - Full certificate chain

### HTTPS-Only Security

Prometheus is configured for HTTPS-only access. The HTTP port (9090) is not exposed externally, ensuring all traffic goes through Traefik's secure HTTPS endpoint. This provides:
- ✅ Mandatory encryption for all connections
- ✅ No plaintext HTTP exposure
- ✅ Centralized certificate management via Traefik

If you need to expose HTTP for development purposes, add a port mapping in `docker-compose.yml`:

```yaml
prometheus:
  ports:
    - "9090:9090"  # HTTP access (not recommended for production)
```

Then restart Prometheus:
```bash
docker compose restart prometheus
```

## Troubleshooting

### Certificate not found

If you see errors like "certificate not found", ensure:
1. Certificate files exist: `./certs/prometheus.local.crt` and `./certs/prometheus.local.key`
2. Traefik can read the files (check permissions)
3. Paths in `dynamic.yml` are correct

```bash
ls -la ./certs/prometheus.local.*
```

### Traefik not routing to Prometheus

Check Traefik logs:
```bash
docker compose logs -f traefik
```

Verify the router rule matches your domain:
```bash
# Should show 200 OK
curl -k -H "Host: prometheus.local" https://127.0.0.1:8443
```

### Browser untrusted certificate warning

This is expected if the Root CA is not trusted by your OS. Either:
1. Import the Root CA (`./certs/root_ca.crt`) into your system trust store
2. Add an exception in your browser (development only)

### Prometheus unable to scrape targets

If Prometheus cannot resolve targets:
- Ensure all services are on the same Docker network (`shared-services`)
- Use service names (e.g., `http://vault:8201`) not localhost
- Check network connectivity: `docker compose exec prometheus wget -qO- http://vault:8201`

## Customization

### Using a Custom Domain

If you use a different domain (e.g., `prometheus.example.com`):

```powershell
# Generate certificate for custom domain
.\scripts\generate-certs-vault.ps1 -Domain "prometheus.example.com"
```

Update `docker-compose.yml`:
```yaml
labels:
  - "traefik.http.routers.prometheus.rule=Host(`prometheus.example.com`)"
```

Update `config/traefik/dynamic.yml`:
```yaml
routers:
  prometheus:
    rule: "Host(`prometheus.example.com`)"

tls:
  certificates:
    - certFile: /certs/prometheus.example.com.crt
      keyFile: /certs/prometheus.example.com.key
```

Update your hosts file or DNS records:
```
127.0.0.1  prometheus.example.com
```

## Integration with Services

Prometheus is configured to scrape metrics from various services. Check `config/prometheus.yml` for scrape targets.

Access Prometheus securely via HTTPS through Traefik while it scrapes metrics from services internally via HTTP.

### Querying Prometheus

**Via Web UI:**
```
https://prometheus.local:8443
```

**Via API (through Traefik):**
```bash
curl -k "https://prometheus.local:8443/api/v1/query?query=up"
```

**Internal (from Grafana):**
Grafana connects to Prometheus internally:
```yaml
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/)
- [Vault PKI Documentation](https://www.vaultproject.io/docs/secrets/pki)
- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
