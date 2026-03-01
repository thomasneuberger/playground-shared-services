# 🔐 Keycloak HTTPS with Vault PKI Certificate (Traefik TLS Termination)

Configure Keycloak to use HTTPS via Traefik, with certificates from the Vault PKI Engine.

**Architecture:**
- Keycloak listens on HTTP (port 8080)
- Traefik handles TLS termination with Vault PKI certificates
- Clean separation of concerns (Keycloak doesn't manage certificates)

## Overview

This guide shows how to:
1. Generate a server certificate for Keycloak from Vault PKI
2. Configure Traefik to route HTTPS traffic to Keycloak
3. Access Keycloak securely via HTTPS

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

Run the generate-certs script to create a Keycloak certificate from Vault PKI:

```powershell
# Windows
.\scripts\generate-certs-vault.ps1 -Domain "keycloak.local"

# Or with custom domain and IP SANs
.\scripts\generate-certs-vault.ps1 -Domain "auth.example.com" -IpSans "192.168.1.10"
```

**Linux/macOS:**
```bash
./scripts/generate-certs-vault.sh -d keycloak.local
./scripts/generate-certs-vault.sh -d auth.example.com -i 192.168.1.10
```

The script will:
- ✅ Generate certificate from Vault PKI
- ✅ Save `keycloak.local.crt` and `keycloak.local.key`
- ✅ Export Root CA as `root_ca.crt`
- ✅ Create additional files (ca-chain, bundle) for reference

### Step 2: Verify docker-compose.yml

Keycloak is already configured with Traefik labels. Verify the following in `docker-compose.yml`:

```yaml
keycloak:
  image: quay.io/keycloak/keycloak:latest
  ports:
    - "8082:8080"      # HTTP only (Traefik proxies this)
  environment:
    KC_HOSTNAME: keycloak.local
    KC_PROXY: edge
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.keycloak.rule=Host(`keycloak.local`)"
    - "traefik.http.routers.keycloak.entrypoints=websecure"
    - "traefik.http.routers.keycloak.tls=true"
    - "traefik.http.services.keycloak.loadbalancer.server.port=8080"
```

### Step 3: Verify Traefik Configuration

Traefik is configured to use the Keycloak certificate. Check `config/traefik/dynamic.yml`:

```yaml
http:
  routers:
    keycloak:
      rule: "Host(`keycloak.local`)"
      entryPoints:
        - websecure
      service: keycloak-service
      tls: {}
  
  services:
    keycloak-service:
      loadBalancer:
        servers:
          - url: "http://keycloak:8080"

tls:
  certificates:
    - certFile: /certs/keycloak.local.crt
      keyFile: /certs/keycloak.local.key
```

This is already in place. No manual configuration needed!

### Step 4: Restart Services

```bash
docker compose up -d

# Wait for services to be ready
sleep 10

# Check logs
docker compose logs -f traefik keycloak
```

### Step 5: Access Keycloak via HTTPS

```
https://keycloak.local/admin
```

**Login with:**
- Username: `admin` (from `env:KEYCLOAK_ADMIN`)
- Password: (from `.env:KEYCLOAK_ADMIN_PASSWORD`)

### Step 6: Trust the Root CA (Optional)

Your browser may warn about the certificate. To trust it:

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

## Configuration Details

### Environment Variables

Update `.env` if using a custom domain:

```bash
# .env (optional - defaults to keycloak.local)
KEYCLOAK_DOMAIN=auth.example.com
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=Change_Me_Admin_123!
```

### Custom Domain

To use a different domain:

1. **Generate certificate:**
   ```powershell
   .\scripts\setup-keycloak-vault-cert.ps1 -Domain "auth.mycompany.com"
   ```

2. **Update docker-compose.yml:**
   ```yaml
   environment:
     KEYCLOAK_DOMAIN: auth.mycompany.com
   labels:
     - "traefik.http.routers.keycloak.rule=Host(`auth.mycompany.com`)"
   ```

3. **Update traefik/dynamic.yml:**
   ```yaml
   tls:
     certificates:
       - certFile: /certs/auth.mycompany.com.crt
         keyFile: /certs/auth.mycompany.com.key
   ```

4. **Restart services:**
   ```bash
   docker compose up -d
   ```

### Multiple SANs (Subject Alternative Names)

Include multiple domains and IP addresses in the certificate:

```powershell
.\scripts\setup-keycloak-vault-cert.ps1 `
  -Domain "keycloak.local" `
  -IpSans "127.0.0.1,192.168.178.60"
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Client (Browser)                                    │
│ https://keycloak.local/admin                        │
└──────────────────┬──────────────────────────────────┘
                   │ TLS/HTTPS
                   ▼
┌─────────────────────────────────────────────────────┐
│ Traefik (Port 443)                                  │
│ ✅ TLS Termination                                  │
│ ✅ Certificate: keycloak.local.crt / .key           │
│ ✅ From Vault PKI                                   │
└──────────────────┬──────────────────────────────────┘
                   │ HTTP (internal)
                   ▼
┌─────────────────────────────────────────────────────┐
│ Keycloak Container (Port 8080)                      │
│ HTTP only (no TLS needed)                           │
│ Configured with KC_PROXY=edge                       │
└─────────────────────────────────────────────────────┘
```

## Troubleshooting

### Traefik not routing to Keycloak

Check Traefik logs:
```bash
docker compose logs traefik | grep keycloak
```

Ensure hostname matches in docker-compose.yml and traefik/dynamic.yml.

### Certificate loading issues

Verify certificate files exist:
```bash
ls -la certs/keycloak.local.*
```

Check certificate details:
```powershell
openssl x509 -in certs/keycloak.local.crt -text -noout
```

### SSL_ERROR_UNRECOGNIZED_NAME in browser

The certificate's Common Name or Alt Names don't match the hostname. Regenerate:

```powershell
.\scripts\setup-keycloak-vault-cert.ps1 -Domain "keycloak.local"
```

### Connection refused

Keycloak not responding on port 8080:

```bash
docker compose logs keycloak | grep -i "started\|error"
```

Check health endpoint:
```bash
curl http://localhost:8082/health
```

### Traefik using wrong certificate

Verify certificate order in `traefik/dynamic.yml`. The default certificate is used for SNI mismatches. Ensure Keycloak router uses the correct certificate.

## Advanced Configuration

### Force HTTPS Redirect

Optional: Redirect HTTP to HTTPS:

```yaml
# docker-compose.yml - traefik
command:
  - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
  - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
```

Then uncomment in dynamic.yml:

```yaml
http:
  routers:
    keycloak-redirect:
      rule: "Host(`keycloak.local`)"
      service: keycloak-service
      entrypoints:
        - web
      middlewares:
        - redirect-https
  
  middlewares:
    redirect-https:
      redirectScheme:
        scheme: https
        permanent: true
```

### Certificate Renewal

Generate new certificate before expiration:

```powershell
# Regenerate with the same domain
.\scripts\setup-keycloak-vault-cert.ps1 -Domain "keycloak.local"

# Restart Traefik and Keycloak to load new certificate
docker compose restart traefik keycloak
```

Check certificate expiration:

```bash
openssl x509 -in certs/keycloak.local.crt -noout -dates
```

### mTLS (Client Certificates)

For mutual TLS between Traefik and Keycloak:

1. Generate client certificate:
   ```powershell
   .\scripts\generate-certs-vault.ps1 -CommonName "traefik" -Role "client-cert"
   ```

2. Update traefik middleware (advanced):
   ```yaml
   middlewares:
     mtls:
       clientAuth:
         clientAuthType: RequireAndVerifyClientCert
         caFiles:
           - /certs/root_ca.crt
   ```

## Integration Examples

### ASP.NET Core Integration

Trust the Vault CA when calling Keycloak:

```csharp
var handler = new HttpClientHandler();

// Trust Vault's Root CA
var caCertPath = "./certs/root_ca.crt";
if (File.Exists(caCertPath))
{
    var caCert = new X509Certificate2(caCertPath);
    handler.ServerCertificateCustomValidationCallback = (msg, cert, chain, errors) =>
    {
        if (errors == SslPolicyErrors.None)
            return true;
        
        // Add Vault CA to chain for validation
        chain.ChainPolicy.CustomTrustStore.Add(caCert);
        return chain.Build(cert);
    };
}

builder.Services.AddHttpClient<KeycloakClient>()
    .ConfigureHttpClient(http =>
    {
        http.BaseAddress = new Uri("https://keycloak.local");
        http.DefaultRequestHeaders.Add("Accept", "application/json");
    })
    .ConfigurePrimaryHttpMessageHandler(() => handler);
```

### Node.js/Express Integration

```javascript
const https = require('https');
const fs = require('fs');

// Load Root CA
const rootCA = fs.readFileSync('./certs/root_ca.crt');

const agent = new https.Agent({
  ca: rootCA
});

fetch('https://keycloak.local/realms/myapp/.well-known/openid-configuration', {
  agent: agent
})
.then(res => res.json())
.then(config => console.log(config))
.catch(err => console.error(err));
```

### Python Integration

```python
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.ssl_ import create_urllib3_context

session = requests.Session()

# Trust Vault CA
session.verify = './certs/root_ca.crt'

response = session.get(
    'https://keycloak.local/admin',
    headers={'Accept': 'application/json'}
)
print(response.json())
```

## Differences from Keycloak's Native HTTPS

| Aspect | Traefik (Current) | Keycloak Native |
|--------|------------------|-----------------|
| **TLS Termination** | Traefik | Keycloak |
| **Certificate Management** | Vault PKI + Traefik | Keycloak JKS keystore |
| **Certificate Format** | PEM (.crt, .key) | JKS (Java keystore) |
| **Prerequisites** | Vault CLI | Java keytool |
| **Keycloak Complexity** | Simpler (HTTP only) | More complex |
| **Scalability** | Better (Traefik handles TLS) | Per-instance |
| **Production Ready** | ✅ Yes | ✅ Yes |

## Security Best Practices

### 1. Use Strong Hostname Verification

Keep `KC_HOSTNAME_STRICT: 'true'` enabled.

### 2. Restrict Certificate Permissions

```bash
chmod 600 certs/keycloak.local.key
chmod 644 certs/keycloak.local.crt
```

### 3. Rotate Certificates Regularly

Set up automated renewal (example with cron):

```bash
# Renew certificate every month (1st of month at 02:00)
0 2 1 * * cd /path/to/playground-shared-services && \
  ./scripts/setup-keycloak-vault-cert.sh -d keycloak.local && \
  docker compose restart traefik keycloak
```

### 4. Monitor Certificate Expiration

```bash
# View expiration
openssl x509 -in certs/keycloak.local.crt -noout -dates

# Set alerts for 30 days before expiration
openssl x509 -in certs/keycloak.local.crt -noout -checkend 2592000
echo $?  # 0 = valid for 30+ days, 1 = expires soon
```

## References

- [Keycloak HTTPS Configuration](https://www.keycloak.org/server/enabling-https)
- [Traefik Documentation](https://doc.traefik.io/)
- [Vault PKI Engine](https://www.vaultproject.io/docs/secrets/pki)
- [Traefik TLS Configuration](https://doc.traefik.io/traefik/https/tls/)

## Support

For issues:
1. Check certificate exists: `ls -la certs/keycloak.local.*`
2. Check Traefik logs: `docker compose logs traefik`
3. Check Keycloak logs: `docker compose logs keycloak`
4. Verify certificate validity: `openssl x509 -in certs/keycloak.local.crt -text -noout`

