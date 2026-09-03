# 🔐 Loki HTTPS with Vault PKI Certificate (Traefik TLS Termination)

Configure Loki to use HTTPS via Traefik, with certificates from the Vault PKI Engine.

**Architecture:**
- Loki runs internally on port 3100 (not exposed externally)
- Traefik handles TLS termination with Vault PKI certificates
- HTTPS-only access through Traefik
- Clean separation of concerns (Loki doesn't manage certificates)

## Overview

This guide shows how to:
1. Generate a server certificate for Loki from Vault PKI
2. Configure Traefik to route HTTPS traffic to Loki
3. Access Loki securely via HTTPS

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

Run the generate-certs script to create a Loki certificate from Vault PKI:

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "loki.local"

# Or with custom domain and IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "loki.example.com" -IpSans "192.168.1.10"
```

**Linux/macOS:**
```bash
./scripts/generate-certs-vault.sh -d loki.local
./scripts/generate-certs-vault.sh -d loki.example.com -i 192.168.1.10
```

The script will:
- ✅ Generate certificate from Vault PKI
- ✅ Save `loki.local.crt` and `loki.local.key`
- ✅ Export Root CA as `root_ca.crt`
- ✅ Create additional files (ca-chain, bundle) for reference

### Step 2: Verify docker-compose.yml

Loki is already configured with Traefik labels. Verify the following in `docker-compose.yml`:

```yaml
loki:
  image: grafana/loki:latest
  volumes:
    - ./config/loki-config.yml:/etc/loki/local-config.yml:ro
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.loki.rule=Host(`loki.local`)"
    - "traefik.http.routers.loki.entrypoints=websecure"
    - "traefik.http.routers.loki.tls=true"
    - "traefik.http.services.loki.loadbalancer.server.port=3100"
```

### Step 3: Verify Traefik Configuration

Traefik is configured to use the Loki certificate. Check `config/traefik/dynamic.yml`:

```yaml
http:
  routers:
    loki:
      rule: "Host(`loki.local`)"
      entryPoints:
        - websecure
      service: loki-service
      tls: {}
  
  services:
    loki-service:
      loadBalancer:
        servers:
          - url: "http://loki:3100"

tls:
  certificates:
    - certFile: /certs/loki.local.crt
      keyFile: /certs/loki.local.key
```

This is already in place. No manual configuration needed!

### Step 4: Update /etc/hosts (Optional but Recommended)

To access Loki via `https://loki.local`, add an entry to your hosts file:

**Windows (as Administrator):**
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n127.0.0.1`tloki.local"
```

Or edit `C:\Windows\System32\drivers\etc\hosts` directly:
```
127.0.0.1  loki.local
```

**Linux/macOS:**
```bash
sudo sh -c 'echo "127.0.0.1  loki.local" >> /etc/hosts'
```

### Step 5: Restart Services

```bash
docker compose up -d

# Wait for services to be ready
sleep 10

# Check logs
docker compose logs -f traefik loki
```

### Step 6: Access Loki via HTTPS

**Important:** Loki is an **API-only service** and does **not have a web UI**. The root path (/) will return a 404.

To verify Loki is accessible, use these endpoints:

**Health/Ready Check:**
```bash
curl -k https://loki.local:8443/ready
```

**Expected responses:**
- During startup (first ~15s): `Ingester not ready: waiting for 15s after being ready`
- After startup: `ready`

**Note:** Loki's ingester has a built-in 15-second warm-up period after initialization. This is normal behavior.

**Metrics Endpoint:**
```bash
curl -k https://loki.local:8443/metrics
```

**Query API (requires logs to be present):**
```bash
curl -k -G "https://loki.local:8443/loki/api/v1/query_range" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'start=2026-03-01T00:00:00Z' \
  --data-urlencode 'end=2026-03-01T23:59:59Z'
```

**For a Web UI:** Use Grafana's Explore feature at `https://grafana.local:8443` → Explore → Select Loki datasource.

---

**Note:** Loki is **only** accessible via HTTPS through Traefik. Direct HTTP access is not available.

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

When you access `https://loki.local:8443`:
1. Traefik receives the HTTPS request on port 8443 (mapped to internal port 443)
2. Matches the hostname `loki.local` against the router rules
3. Loads the corresponding TLS certificate (`loki.local.crt` + `loki.local.key`)
4. Decrypts the request and proxies it to Loki's internal port 3100

### Certificate Locations

Certificates are stored in the `./certs/` directory:
- `loki.local.crt` - Server certificate
- `loki.local.key` - Private key
- `root_ca.crt` - Root CA certificate (trust this in your OS)
- `ca_chain.crt` - Full certificate chain

### HTTPS-Only Security

Loki is configured for HTTPS-only access. The HTTP port (3100) is not exposed externally, ensuring all traffic goes through Traefik's secure HTTPS endpoint. This provides:
- ✅ Mandatory encryption for all connections
- ✅ No plaintext HTTP exposure
- ✅ Centralized certificate management via Traefik

If you need to expose HTTP for development purposes, add a port mapping in `docker-compose.yml`:

```yaml
loki:
  ports:
    - "3100:3100"  # HTTP access (not recommended for production)
```

Then restart Loki:
```bash
docker compose restart loki
```

## Troubleshooting

### Certificate not found

If you see errors like "certificate not found", ensure:
1. Certificate files exist: `./certs/loki.local.crt` and `./certs/loki.local.key`
2. Traefik can read the files (check permissions)
3. Paths in `dynamic.yml` are correct

```bash
ls -la ./certs/loki.local.*
```

### Traefik not routing to Loki

Check Traefik logs:
```bash
docker compose logs -f traefik
```

Verify the router rule matches your domain:
```bash
# Should show "ready" or metrics
curl -k -H "Host: loki.local" https://127.0.0.1:8443/ready
curl -k -H "Host: loki.local" https://127.0.0.1:8443/metrics
```

**Note:** The root path (/) will return 404 - this is normal. Loki has no web UI.

### Browser untrusted certificate warning

This is expected if the Root CA is not trusted by your OS. Either:
1. Import the Root CA (`./certs/root_ca.crt`) into your system trust store
2. Add an exception in your browser (development only)

### Loki reports "Ingester not ready"

This is **normal during startup**. Loki's ingester component has a 15-second warm-up period:

```bash
# During first ~15 seconds after container start
curl -k https://loki.local:8443/ready
# Returns: Ingester not ready: waiting for 15s after being ready
```

**Solution:** Wait 15-20 seconds after starting the Loki container, then check again:
```bash
# After ~15-20 seconds
curl -k https://loki.local:8443/ready
# Returns: ready
```

If it persists beyond 30 seconds, check the logs:
```bash
docker compose logs loki
```

### Grafana unable to reach Loki

If Grafana cannot query Loki:
- Ensure all services are on the same Docker network (`shared-services`)
- Use service names (e.g., `http://loki:3100`) not localhost in Grafana datasource config
- Check network connectivity: `docker compose exec grafana wget -qO- http://loki:3100/ready`

## Customization

### Using a Custom Domain

If you use a different domain (e.g., `loki.example.com`):

```powershell
# Generate certificate for custom domain
.\scripts\generate-certs-vault.ps1 -Domain "loki.example.com"
```

Update `docker-compose.yml`:
```yaml
labels:
  - "traefik.http.routers.loki.rule=Host(`loki.example.com`)"
```

Update `config/traefik/dynamic.yml`:
```yaml
routers:
  loki:
    rule: "Host(`loki.example.com`)"

tls:
  certificates:
    - certFile: /certs/loki.example.com.crt
      keyFile: /certs/loki.example.com.key
```

Update your hosts file or DNS records:
```
127.0.0.1  loki.example.com
```

## Integration with Services

Loki is configured to receive logs from various services. Access Loki securely via HTTPS through Traefik while it receives logs from services internally.

### Querying Loki

**Via Web UI (through Grafana):**
```
https://grafana.local:8443 → Explore → Loki
```

**Via API (through Traefik):**
```bash
# Query logs
curl -k -G "https://loki.local:8443/loki/api/v1/query_range" \
  --data-urlencode 'query={job="varlogs"}' \
  --data-urlencode 'start=2026-03-01T00:00:00Z' \
  --data-urlencode 'end=2026-03-01T23:59:59Z'

# Check readiness
curl -k "https://loki.local:8443/ready"
```

**Internal (from Grafana datasource):**
Grafana connects to Loki internally:
```yaml
datasources:
  - name: Loki
    type: loki
    url: http://loki:3100
```

### Sending Logs to Loki

Applications should send logs to Loki's internal endpoint:
```
http://loki:3100
```

Example with Promtail:
```yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
```

## References

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Traefik Documentation](https://doc.traefik.io/)
- [Vault PKI Documentation](https://www.vaultproject.io/docs/secrets/pki)
- [LogQL (Loki Query Language)](https://grafana.com/docs/loki/latest/logql/)
