# 🔒 HTTPS for Vault UI with Traefik

This guide shows how to enable HTTPS for the Vault UI using **Traefik** as a reverse proxy with certificates from Vault's PKI engine.

## 🎯 Solution: Traefik Reverse Proxy

**Advantages:**
- ✅ Keep Vault in dev mode (easy, auto-unsealed)
- ✅ HTTPS termination at proxy layer
- ✅ Automatic service discovery
- ✅ No manual Vault unsealing required
- ✅ Perfect for local development and testing

**How it works:**
```
Browser (HTTPS) → Traefik (Port 8443) → Vault (HTTP, Port 8200)
```

---

## 🚀 Quick Start

### Step 1: Generate Certificate for Traefik

```powershell
# Make sure Vault is running
docker compose up -d vault vault-pki-init

# Wait for PKI initialization
docker compose logs -f vault-pki-init

# Generate certificate for Vault UI
.\scripts\generate-certs-vault.ps1 `
    -Domain "vault.local,localhost" `
    -IpSans "127.0.0.1" `
    -Role "service-cert"
```

This creates:
- `certs/vault.local.crt` - Certificate with CA chain (used by Traefik/Nginx/server)
- `certs/vault.local.key` - Private key  
- `certs/root_ca.crt` - Root CA (for browser trust)

### Step 2: Add Traefik to docker-compose.yml

Add this service to your `docker-compose.yml`:

```yaml
  # === TRAEFIK REVERSE PROXY FOR VAULT HTTPS ===
  traefik:
    image: traefik:v2.11
    container_name: shared-traefik
    ports:
      - "8443:443"      # HTTPS for Vault UI
      - "8080:8080"     # Traefik Dashboard (optional)
    command:
      # Enable Docker provider
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      
      # Entry points
      - "--entrypoints.websecure.address=:443"
      
      # Enable dashboard (optional)
      - "--api.dashboard=true"
      - "--api.insecure=true"
      
      # Logging
      - "--log.level=INFO"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - ./config/traefik:/etc/traefik:ro
      - ./certs:/certs:ro
    networks:
      - shared-services
    restart: unless-stopped
    labels:
      - "traefik.enable=true"
      # Dashboard routing (optional)
      - "traefik.http.routers.dashboard.rule=Host(`traefik.localhost`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.entrypoints=web"
```

### Step 3: Update Vault Service Labels

Update your existing `vault` service in `docker-compose.yml` to add Traefik labels:

```yaml
  vault:
    image: hashicorp/vault:latest
    container_name: shared-vault
    ports:
      - "8201:8200"
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: ${VAULT_TOKEN:-myroot123}
      VAULT_DEV_LISTEN_ADDRESS: "0.0.0.0:8200"
      VAULT_ADDR: "http://127.0.0.1:8200"
    cap_add:
      - IPC_LOCK
    volumes:
      - vault-data:/vault/data
      - vault-logs:/vault/logs
      - ./certs:/vault/certs
      - ./config/vault:/vault/config:ro
    networks:
      - shared-services
    restart: unless-stopped
    command: server -dev
    healthcheck:
      test: ["CMD", "vault", "status"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 20s
    labels:
      # Enable Traefik for this service
      - "traefik.enable=true"
      
      # Router configuration
      - "traefik.http.routers.vault.rule=Host(`vault.local`) || Host(`localhost`)"
      - "traefik.http.routers.vault.entrypoints=websecure"
      - "traefik.http.routers.vault.tls=true"
      
      # Service configuration
      - "traefik.http.services.vault.loadbalancer.server.port=8200"
      
      # TLS configuration
      - "traefik.http.routers.vault.tls.certresolver=vault-pki"
```

### Step 4: Create Traefik Configuration

Create `config/traefik/traefik.yml`:

```yaml
# Traefik Static Configuration
api:
  dashboard: true
  insecure: true

providers:
  docker:
    exposedByDefault: false
    network: shared-services
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

entryPoints:
  websecure:
    address: ":443"

log:
  level: INFO
```

Create `config/traefik/dynamic.yml`:

```yaml
# Traefik Dynamic Configuration
tls:
  certificates:
    - certFile: /certs/vault.local.crt
      keyFile: /certs/vault.local.key
  stores:
    default:
      defaultCertificate:
        certFile: /certs/vault.local.crt
        keyFile: /certs/vault.local.key
```

### Step 5: Add Hostname to Windows Hosts File (Optional)

If using `vault.local` domain:

```powershell
# Run as Administrator
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "127.0.0.1 vault.local"
```

Or edit `C:\Windows\System32\drivers\etc\hosts` and add:
```
127.0.0.1 vault.local
```

### Step 6: Trust Root CA Certificate

```powershell
# Windows - Run as Administrator
certutil -addstore -f "ROOT" ".\certs\root_ca.crt"

# Verify installation
certutil -store ROOT | Select-String "Shared Services"
```

**Linux:**
```bash
sudo cp ./certs/root_ca.crt /usr/local/share/ca-certificates/vault-pki-ca.crt
sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain ./certs/root_ca.crt
```

### Step 7: Start Services

```powershell
# Start all services
docker compose up -d

# Check logs
docker compose logs -f traefik
docker compose logs -f vault
```

### Step 8: Access Vault UI via HTTPS

Open in your browser:
- **Vault UI**: https://localhost:8443
- **Vault UI (with hostname)**: https://vault.local:8443
- **Traefik Dashboard** (optional): http://localhost:8080

Login with your Vault token from `.env` file.

---

## 📁 Complete Directory Structure

```
playground-shared-services/
├── certs/
│   ├── vault.local.crt          # Generated certificate
│   ├── vault.local.key          # Private key
│   ├── vault.local-bundle.crt   # Certificate bundle
│   └── root_ca.crt              # Root CA for trust
├── config/
│   ├── traefik/
│   │   ├── traefik.yml          # Static configuration
│   │   └── dynamic.yml          # Dynamic/TLS configuration
│   └── vault/
│       └── init-pki.sh
├── docker-compose.yml
└── .env
```

---

## 🔧 Alternative: Simple Traefik Setup (File-based)

If you prefer a simpler configuration without Docker labels:

**docker-compose.yml:**
```yaml
  traefik:
    image: traefik:v2.11
    container_name: shared-traefik
    ports:
      - "8443:443"
    command:
      - "--providers.file.filename=/etc/traefik/dynamic.yml"
      - "--entrypoints.websecure.address=:443"
      - "--log.level=INFO"
    volumes:
      - ./config/traefik:/etc/traefik:ro
      - ./certs:/certs:ro
    networks:
      - shared-services
    depends_on:
      - vault
    restart: unless-stopped
```

**config/traefik/dynamic.yml:**
```yaml
http:
  routers:
    vault:
      rule: "Host(`vault.local`) || Host(`localhost`)"
      entryPoints:
        - websecure
      service: vault-service
      tls: {}
  
  services:
    vault-service:
      loadBalancer:
        servers:
          - url: "http://vault:8200"

tls:
  certificates:
    - certFile: /certs/vault.local.crt
      keyFile: /certs/vault.local.key
```

---

## 🎨 Customization Options

### 1. Use Different Domain

```powershell
# Generate cert for custom domain
.\scripts\generate-certs-vault.ps1 -Domain "myvault.local" -IpSans "127.0.0.1"

# Update Traefik router rule
- "traefik.http.routers.vault.rule=Host(`myvault.local`)"

# Add to hosts file
127.0.0.1 myvault.local
```

### 2. Enable HTTP → HTTPS Redirect

Add to Vault service labels:
```yaml
      # HTTP to HTTPS redirect
      - "traefik.http.routers.vault-http.rule=Host(`vault.local`)"
      - "traefik.http.routers.vault-http.entrypoints=web"
      - "traefik.http.routers.vault-http.middlewares=redirect-to-https"
      - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
```

Don't forget to add port 80:
```yaml
      - "8080:80"     # HTTP
      - "8443:443"    # HTTPS
```

### 3. Custom Port

```yaml
    ports:
      - "9443:443"  # Use port 9443 instead
```

Access: https://localhost:9443

### 4. Multiple Services with HTTPS

Traefik can handle multiple services:

```yaml
  keycloak:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.keycloak.rule=Host(`keycloak.local`)"
      - "traefik.http.routers.keycloak.entrypoints=websecure"
      - "traefik.http.routers.keycloak.tls=true"
      - "traefik.http.services.keycloak.loadbalancer.server.port=8080"
```

---

## 🐛 Troubleshooting

### Certificate Not Trusted / "Your connection is not private"

**Solution 1**: Trust the Root CA
```powershell
certutil -addstore -f "ROOT" ".\certs\root_ca.crt"
```

**Solution 2**: Skip verification in browser (Chrome)
- Type `thisisunsafe` on the warning page (no input box needed)

### Traefik Can't Find Certificate Files

```powershell
# Check if files exist
ls .\certs\vault.local.crt
ls .\certs\vault.local.key

# Check Traefik logs
docker compose logs traefik

# Verify volume mount
docker compose exec traefik ls -la /certs
```

### "Bad Gateway" Error

```powershell
# Check if Vault is running
docker compose ps vault

# Check if Vault is healthy
docker compose exec vault vault status

# Check network connectivity
docker compose exec traefik ping vault
```

### Traefik Dashboard Not Accessible

Make sure dashboard is enabled:
```yaml
    command:
      - "--api.dashboard=true"
      - "--api.insecure=true"  # Only for local dev!
```

Access: http://localhost:8080

### Certificate Expired

```powershell
# Check certificate validity
openssl x509 -in .\certs\vault.local.crt -noout -dates

# Regenerate certificate
.\scripts\generate-certs-vault.ps1 -Domain "vault.local" -IpSans "127.0.0.1"

# Restart Traefik to reload
docker compose restart traefik
```

---

## 🚀 Production Considerations

### For NAS or Remote Deployment

1. **Generate certificate with actual hostname:**
   ```powershell
   .\scripts\generate-certs-vault.ps1 `
       -Domain "vault.mynas.local" `
       -IpSans "192.168.1.100" `
       -Role "service-cert"
   ```

2. **Use Let's Encrypt with Traefik:**
   ```yaml
     command:
       - "--certificatesresolvers.letsencrypt.acme.email=your@email.com"
       - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
       - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
   ```

3. **Enable access logs:**
   ```yaml
     command:
       - "--accesslog=true"
       - "--accesslog.filepath=/var/log/traefik/access.log"
   ```

4. **Disable insecure dashboard:**
   ```yaml
     command:
       - "--api.dashboard=true"
       # Remove: - "--api.insecure=true"
   ```

   Then protect with authentication:
   ```yaml
   labels:
     - "traefik.http.routers.dashboard.middlewares=auth"
     - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$..."
   ```

---

## 📊 Comparison with Other Solutions

| Solution | Complexity | Auto-Unseal | HTTPS | Best For |
|----------|------------|-------------|-------|----------|
| **Traefik Proxy** | ⭐ Low | ✅ Yes | ✅ Yes | Local dev, Docker |
| Nginx Proxy | ⭐⭐ Medium | ✅ Yes | ✅ Yes | Traditional setups |
| Vault Server Mode | ⭐⭐⭐ High | ❌ No | ✅ Yes | Production |
| Caddy Proxy | ⭐ Low | ✅ Yes | ✅ Yes | Auto-HTTPS needs |

---

## 📚 Additional Resources

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik Docker Provider](https://doc.traefik.io/traefik/providers/docker/)
- [Traefik TLS Configuration](https://doc.traefik.io/traefik/https/tls/)
- [Vault PKI Setup](PKI_SETUP_VAULT.md)
- [Generate Certificates Script](scripts/README_VAULT_PKI.md)

---

## ✅ Summary

You now have:
- ✅ Vault running in dev mode (easy, auto-unsealed)
- ✅ HTTPS access via Traefik reverse proxy
- ✅ Valid TLS certificate from Vault PKI
- ✅ Trusted Root CA in your system
- ✅ Access Vault UI at https://localhost:8443

**No manual unsealing required!** 🎉
