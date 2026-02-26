# Keycloak Setup für Identity Management

Keycloak ist eine Enterprise-Grade Open-Source Identity Management Lösung mit OpenID Connect, OAuth2 und SAML Support.

## 🚀 Quick Start

### 1. Keycloak starten

```bash
docker compose up -d keycloak-db keycloak

# Status überprüfen
docker compose logs -f keycloak

# Health Check
curl http://localhost:8080/health
```

### 2. Admin Console öffnen

```
http://localhost:8080/admin
```

**Login:**
- Username: `admin` (aus .env `KEYCLOAK_ADMIN`)
- Passwort: `<KEYCLOAK_ADMIN_PASSWORD>` (aus .env)

## 🏗️ Realm Setup

Ein **Realm** ist eine logische Isolation von Benutzern, Clients und Rollen.

### Realm erstellen

1. Admin Console → „Master" Dropdown (oben links)
2. → „Create Realm"
3. **Name:** `myapp`
4. **Enabled:** ON
5. **Create**

### Realm Security & Settings

1. Realm Settings → General
   - Display Name: "My Application"
   - Display Name HTML: "My Application"

2. Realm Settings → Tokens
   - Access Token Lifespan: 1 hour
   - Refresh Token Lifespan: 7 days
   - SSO Session Idle: 30 minutes

3. Realm Settings → Email
   - Host: `smtp.example.com`
   - From: `noreply@example.com`

## 👥 Client (Application) Setup

Ein Client ist eine Anwendung, die Keycloak nutzt.

### Neuen Client registrieren

1. Realm `myapp` auswählen
2. Left Sidebar → Clients → Create
3. **Client ID:** `myapp-api`
4. **Next**

### Client Configuration

#### General

- **Client Protocol:** `openid-connect`
- **Access Type:** `confidential` (für Backend-Apps mit Secret)
- **Standard Flow Enabled:** ON
- **Direct Access Grants Enabled:** ON (für Testing)
- **Service Accounts Enabled:** ON (für Service-to-Service)

#### Redirect URIs

**⚠️ Replace `localhost:5001` with your actual application port!**

```
http://localhost:5001/*
http://localhost:5001/swagger/oauth2-redirect.html
http://myapp.local/*
```

#### Web Origins

**⚠️ These should match your application's domain/port!**

```
http://localhost:5001
http://myapp.local
```

#### Credentials

Nach dem Speichern → Credentials Tab → Copy Client Secret

```
KEYCLOAK_CLIENT_SECRET=xxxxx
```

### Beispiel: Web-App Client (Authority Code Flow)

```yaml
# docker-compose.yml
environment:
  OIDC:
    Authority: "http://keycloak:8080/realms/myapp"
    ClientId: "myapp-web"
    ClientSecret: "xxxxx"
    RedirectUri: "http://localhost:3000/callback"
```

### Beispiel: Backend Service Client (Client Credentials)

```yaml
environment:
  OIDC:
    Authority: "http://keycloak:8080/realms/myapp"
    ClientId: "myapp-service"
    ClientSecret: "xxxxx"
    Scope: "openid profile email api"
```

## 👤 User Management

### User erstellen

1. Realm `myapp` → Users → Add User
2. **Username:** `testuser`
3. **Email:** `test@example.com`
4. **First Name:** `Test`
5. **Last Name:** `User`
6. **User Enabled:** ON
7. **Create**

### Passwort setzen

1. User auswählen
2. → Credentials Tab
3. → Set Password
4. **Temporary:** OFF (wenn permanent)

### Rollen zuweisen

1. User auswählen
2. → Role Mappings Tab
3. **Assign roles** → Rollen wählen

## 🎯 Rollen & Permissions

### Realm Roles erstellen

1. Realm `myapp` → Roles → Create Role
2. **Role Name:** `api-admin`
3. **Create**

### Rollen-Hierarchie

```
realm-admin
├── api-admin
├── api-user
└── api-readonly
```

### Rollen Mappings in Client

1. Client `myapp-api` → Role Mappings
2. Full Scope Allowed: ON / oder spezifische Rollen

## 🔐 OpenID Connect (OIDC) Integration

### Discovery Endpoint

```
http://keycloak:8080/realms/myapp/.well-known/openid-configuration
```

### Token Endpoint

```
http://keycloak:8080/realms/myapp/protocol/openid-connect/token
```

### Authorization Endpoint

```
http://keycloak:8080/realms/myapp/protocol/openid-connect/auth
```

### Userinfo Endpoint

```
http://keycloak:8080/realms/myapp/protocol/openid-connect/userinfo
```

## 🔗 ASP.NET Core Integration

### Installation

```bash
dotnet add package Microsoft.AspNetCore.Authentication.OpenIdConnect
dotnet add package Microsoft.IdentityModel.Protocols.OpenIdConnect
```

### Program.cs Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

// OpenID Connect Authentication
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
    options.Scope.Add("email");
    
    options.TokenValidationParameters = new TokenValidationParameters
    {
        NameClaimType = "name",
        RoleClaimType = "realm_access"
    };
});

builder.Services.AddAuthorization();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.Run();
```

### Protected Endpoints

```csharp
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ProtectedController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        var username = User.FindFirst("name")?.Value;
        
        return Ok(new { userId, username, message = "Hello from protected endpoint!" });
    }
    
    [HttpGet("admin-only")]
    [Authorize(Roles = "api-admin")]
    public IActionResult AdminOnly()
    {
        return Ok("Admin only content");
    }
}
```

### Service-to-Service Communication (Client Credentials)

```csharp
// HttpClient Factory für Service-to-Service
public class KeycloakTokenProvider
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    
    public KeycloakTokenProvider(HttpClient httpClient, IConfiguration configuration)
    {
        _httpClient = httpClient;
        _configuration = configuration;
    }
    
    public async Task<string> GetTokenAsync()
    {
        var realm = _configuration["Keycloak:Realm"];
        var clientId = _configuration["Keycloak:ClientId"];
        var clientSecret = _configuration["Keycloak:ClientSecret"];
        
        var request = new HttpRequestMessage(HttpMethod.Post,
            $"http://keycloak:8080/realms/{realm}/protocol/openid-connect/token")
        {
            Content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("grant_type", "client_credentials"),
                new KeyValuePair<string, string>("client_id", clientId),
                new KeyValuePair<string, string>("client_secret", clientSecret),
                new KeyValuePair<string, string>("scope", "openid"),
            })
        };
        
        var response = await _httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        
        var content = await response.Content.ReadAsStringAsync();
        var json = JsonDocument.Parse(content);
        
        return json.RootElement.GetProperty("access_token").GetString();
    }
}

// Registration
builder.Services.AddHttpClient<KeycloakTokenProvider>();

// Usage
public class MyServiceClient
{
    private readonly HttpClient _httpClient;
    private readonly KeycloakTokenProvider _tokenProvider;
    
    public MyServiceClient(HttpClient httpClient, KeycloakTokenProvider tokenProvider)
    {
        _httpClient = httpClient;
        _tokenProvider = tokenProvider;
    }
    
    public async Task<string> CallSecureServiceAsync()
    {
        var token = await _tokenProvider.GetTokenAsync();
        
        var request = new HttpRequestMessage(HttpMethod.Get, "http://other-service/api/data")
        {
            Headers = { { "Authorization", $"Bearer {token}" } }
        };
        
        var response = await _httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        
        return await response.Content.ReadAsStringAsync();
    }
}
```

### appsettings.json

```json
{
  "Keycloak": {
    "Realm": "myapp",
    "Authority": "http://keycloak:8080/realms/myapp",
    "ClientId": "myapp-api",
    "ClientSecret": "your-client-secret-here"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore.Authentication": "Debug"
    }
  }
}
```

## 🛡️ Advanced Features

### User Attributes

Custom User Attributes hinzufügen:

1. User → Attributes
2. Key: `company`
3. Value: `ACME Corp`
4. Add Attribute

Client Scope anpassen, um Attributes in Token zu includieren:

1. Client → Client Scopes → profile-aggregated-claims
2. Mappers → Add Mapper → User Attribute
3. Name: `company`
4. Token Claim Name: `company`

### Identity Provider

Externe IDPs (GitHub, Google, etc.) verknüpfen:

1. Realm → Identity Providers → Create
2. Provider: `github`, `google`, etc.
3. Configure mit OAuth App Credentials

### Federation & LDAP

Bestehende User Directories mit Keycloak verbinden:

1. Realm → User Federation
2. Add Provider: `ldap`, `kerberos`
3. Configure Connection & Sync Settings

## 📊 Monitoring & Logs

### Logs anschauen

```bash
docker compose logs -f keycloak
```

### Health Endpoint

```bash
# Liveness
curl http://localhost:8080/health

# Readiness
curl http://localhost:8080/health/ready
```

### Prometheus Metrics

Keycloak exportiert Metriken für Prometheus:

```yaml
# prometheus.yml
- job_name: 'keycloak'
  static_configs:
    - targets: ['keycloak:8080']
  metrics_path: '/metrics'
```

## 🚀 Production Setup

### HTTPS aktivieren

```yaml
environment:
  KC_HTTPS_ENABLED: 'true'
  KC_HTTPS_PORT: 8443
  KC_HTTPS_KEY_STORE_FILE: /opt/keycloak/certs/keystore.jks
  KC_HTTPS_KEY_STORE_PASSWORD: changeit
  KC_HTTPS_PROTOCOLS: TLSv1.2,TLSv1.3

volumes:
  - ./certs/keystore.jks:/opt/keycloak/certs/keystore.jks:ro
```

### Database für Production

```yaml
# PostgreSQL mit Backup
keycloak-db:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB: keycloak
    POSTGRES_PASSWORD: strong_password_123
  volumes:
    - keycloak-db-data:/var/lib/postgresql/data
    - ./backup:/backup
  backup-script:
    image: postgres:15-alpine
    command: >
      sh -c "pg_dump -U keycloak -h keycloak-db keycloak > /backup/keycloak_$(date +%Y%m%d).sql"
    depends_on:
      - keycloak-db
```

### Scaling & High Availability

```yaml
# Multi-Instance Setup
keycloak-1:
  image: quay.io/keycloak/keycloak:latest
  environment:
    KEYCLOAK_ADMIN: admin
    KEYCLOAK_ADMIN_PASSWORD: password
    KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
    KC_CACHE: infinispan
    KC_CACHE_CONFIG_FILE: cache-ispn-distributed.xml
  command: [start]

keycloak-2:
  image: quay.io/keycloak/keycloak:latest
  environment:
    # Same as keycloak-1
    KC_CACHE: infinispan
  command: [start]

# Nginx als Reverse Proxy / Load Balancer
nginx:
  image: nginx:latest
  ports:
    - "8080:8080"
  volumes:
    - ./nginx.conf:/etc/nginx/nginx.conf:ro
  depends_on:
    - keycloak-1
    - keycloak-2
```

## 🔍 Troubleshooting

### Problem: Connection refused

```bash
# Keycloak läuft noch nicht? Health Check
docker compose exec keycloak curl -f http://localhost:8080/health || echo "Not ready"
```

### Problem: Database migration fails

```bash
# DB Reset (WARNING: Löscht alle Daten!)
docker compose exec keycloak-db psql -U keycloak -c "DROP DATABASE keycloak;"
docker compose exec keycloak-db psql -U keycloak -c "CREATE DATABASE keycloak;"
```

### Problem: Invalid redirect_uri

```
redirect_uri_mismatch: The redirect URI does not match
```

→ Client Settings → Redirect URIs korrekt konfigurieren

### Problem: CORS errors

```bash
# CORS für Web Client aktivieren
# Client → Web Origins → Add "*" (Development only!)
```

## 📚 Weitere Ressourcen

- [Keycloak Official Docs](https://www.keycloak.org/documentation)
- [Keycloak Server Admin Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Keycloak API Reference](https://www.keycloak.org/docs/latest/rest_api_admin/)
- [OpenID Connect Spec](https://openid.net/specs/openid-connect-core-1_0.html)
- [OAuth 2.0 Spec](https://tools.ietf.org/html/rfc6749)

## 📋 Checkliste für Production

- ✅ Admin Password sicher in Vault speichern
- ✅ HTTPS/TLS aktivieren
- ✅ Database mit Backups
- ✅ Load Balancer für Hochverfügbarkeit
- ✅ Logging & Monitoring (Prometheus + Grafana)
- ✅ Email-Konfiguration für User Invitations
- ✅ User Federation (LDAP/AD)
- ✅ Backup & Disaster Recovery
- ✅ Security: Strong Passwords, MFA
- ✅ Token Lifespan anpassen
