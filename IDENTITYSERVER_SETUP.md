# ℹ️ DEPRECATED: IdentityServer Setup

**⚠️ This file is deprecated. The project now uses **Keycloak** for Identity Management.**

Please refer to [KEYCLOAK_SETUP.md](KEYCLOAK_SETUP.md) instead for current authentication setup instructions.

---

# IdentityServer4 Setup für Linux Docker

Da das System auf einem Linux Docker Host läuft, verwenden wir `mcr.microsoft.com/dotnet/aspnet:8.0-alpine` als Runtime Image.

## 🚀 Optionen für IdentityServer

### Option 1: Vorgefertigtes Docker Image (Schnellstart)

Verwende ein vorgefertigtes IdentityServer4 Docker Image:

```yaml
# docker-compose.yml
identityserver:
  image: ghcr.io/duendesoftware/identityserver:latest
  # oder
  image: duendesoftware/identityserver:latest
```

Diese Images sind Linux-basiert und Production-ready.

### Option 2: Selbst gebautes Image (Empfohlen für Custom Config)

Erstelle einen `Dockerfile` für dein IdentityServer Projekt:

```dockerfile
# Dockerfile.identityserver
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS builder

WORKDIR /src
COPY src/IdentityServer.csproj ./
RUN dotnet restore

COPY src/ ./
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine

WORKDIR /app
COPY --from=builder /app/publish .

EXPOSE 5000
ENV ASPNETCORE_URLS="http://+:5000"

ENTRYPOINT ["dotnet", "IdentityServer.dll"]
```

Bauen und starten:

```bash
# Image bauen
docker build -f Dockerfile.identityserver -t mycompany/identityserver:latest .

# docker-compose.yml aktualisieren
identityserver:
  image: mycompany/identityserver:latest
  build:
    context: .
    dockerfile: Dockerfile.identityserver
```

### Option 3: In-Memory/Mock IdentityServer (für Entwicklung)

```yaml
identityserver:
  image: mcr.microsoft.com/dotnet/aspnet:8.0-alpine
  container_name: shared-identityserver
  ports:
    - "5000:5000"
  environment:
    ASPNETCORE_URLS: "http://+:5000"
    ASPNETCORE_ENVIRONMENT: "Development"
  volumes:
    - ./IdentityServer:/app
  working_dir: /app
  command: >
    sh -c "apt-get update &&
           apt-get install -y dotnet-sdk-8.0 &&
           dotnet run"
  networks:
    - shared-services
  depends_on:
    postgres-identity:
      condition: service_healthy
  restart: unless-stopped
```

## 📦 IdentityServer Minimal Beispiel (C#)

Wenn du IdentityServer4 selbst aufsetzen möchtest:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration
    .GetConnectionString("DefaultConnection");

// Add IdentityServer
builder.Services
    .AddIdentityServer()
    .AddDeveloperSigningCredential() // Nur für Dev!
    .AddInMemoryIdentityResources(IdentityServerConfig.IdentityResources)
    .AddInMemoryApiScopes(IdentityServerConfig.ApiScopes)
    .AddInMemoryClients(IdentityServerConfig.Clients)
    .AddResourceOwnerValidator<ResourceOwnerPasswordValidator>()
    .AddProfileService<ProfileService>();

builder.Services.AddAuthentication();

var app = builder.Build();

app.UseRouting();
app.UseIdentityServer();
app.MapControllers();

// Health Check
app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();
```

```csharp
// IdentityServerConfig.cs
public class IdentityServerConfig
{
    public static IEnumerable<IdentityResource> IdentityResources =>
        new List<IdentityResource>
        {
            new IdentityResources.OpenId(),
            new IdentityResources.Profile(),
            new IdentityResources.Email()
        };

    public static IEnumerable<ApiScope> ApiScopes =>
        new List<ApiScope>
        {
            new ApiScope("api", "Default API")
        };

    public static IEnumerable<Client> Clients =>
        new List<Client>
        {
            // Client Credentials Flow
            new Client
            {
                ClientId = "myapp",
                ClientSecrets = { new Secret("secret123".Sha256()) },
                
                AllowedGrantTypes = GrantTypes.ClientCredentials,
                AllowedScopes = { "api" },
                
                AccessTokenLifetime = 3600
            },
            
            // Resource Owner Password Flow (für Service-to-Service)
            new Client
            {
                ClientId = "myservice",
                ClientSecrets = { new Secret("service_secret".Sha256()) },
                
                AllowedGrantTypes = GrantTypes.ResourceOwnerPassword,
                AllowedScopes = { "api" },
                
                AccessTokenLifetime = 3600
            },
            
            // Authorization Code Flow (für Web Apps)
            new Client
            {
                ClientId = "web_app",
                ClientSecrets = { new Secret("web_secret".Sha256()) },
                
                AllowedGrantTypes = GrantTypes.Code,
                RequirePkce = true,
                AllowPlainTextPkce = false,
                
                RedirectUris = { "https://localhost:3000/callback" },
                PostLogoutRedirectUris = { "https://localhost:3000" },
                
                AllowedScopes = {
                    IdentityServerConstants.StandardScopes.OpenId,
                    IdentityServerConstants.StandardScopes.Profile,
                    "api"
                }
            }
        };
}
```

```csharp
// appsettings.json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=postgres-identity;Database=identityserver;User=identity_user;Password=Change_Me_123!"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "IdentityServer": "Debug"
    }
  },
  "Serilog": {
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "theme": "Serilog.Sinks.SystemConsole.Themes.AnsiConsoleTheme::Code, Serilog.Sinks.Console"
        }
      }
    ]
  }
}
```

## 🔐 Mit Vault Secrets Integieren

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

// Vault Integration
var vaultAddr = Environment.GetEnvironmentVariable("VAULT_ADDR") ?? "http://vault:8200";
var vaultToken = Environment.GetEnvironmentVariable("VAULT_TOKEN");

var authMethod = new TokenAuthMethodInfo(vaultToken);
var vaultClientSettings = new VaultClientSettings(vaultAddr, authMethod);
var vaultClient = new VaultClient(vaultClientSettings);

builder.Configuration.AddVault(vaultClient, "secret/data/identityserver");

// Rest of setup...
```

## 🗄️ Datenbank-Migrations für IdentityServer

```bash
# In einem Init-Container
docker run --rm \
  --network shared-services \
  -e "ConnectionStrings__DefaultConnection=Host=postgres-identity;Database=identityserver;User=identity_user;Password=Change_Me_123!" \
  mycompany/identityserver:latest \
  /bin/sh -c "dotnet ef database update --startup-project ."
```

Oder als Init-Script:

```yaml
# docker-compose.yml
identityserver-migrator:
  image: mycompany/identityserver:latest
  container_name: shared-identityserver-migrate
  environment:
    ConnectionStrings__DefaultConnection: "Host=postgres-identity;Port=5432;Database=${IDENTITY_DB_NAME:-identityserver};User=${IDENTITY_DB_USER:-identity_user};Password=${IDENTITY_DB_PASSWORD:-Change_Me_123!}"
  networks:
    - shared-services
  depends_on:
    postgres-identity:
      condition: service_healthy
  command: >
    /bin/sh -c "dotnet ef database update --startup-project . && echo 'Migration complete'"
  restart: "no"  # Nur einmal ausführen
```

## 🚀 Starten

### Nur mit Demo Config (No Database)

```bash
docker-compose up -d postgres-identity identityserver
```

### Mit Vault Integration

```yaml
# docker-compose.yml
identityserver:
  # ...
  environment:
    VAULT_ADDR: "http://vault:8200"
    VAULT_TOKEN: ${VAULT_TOKEN}
  depends_on:
    - vault
```

## 🔍 Debugging

```bash
# Logs anschauen
docker-compose logs -f identityserver

# In Container gehen
docker-compose exec identityserver sh

# Health Check
curl http://localhost:5000/health

# OpenID Discovery
curl http://localhost:5000/.well-known/openid-configuration
```

## 📝 NuGet Dependencies

```bash
dotnet add package IdentityServer4
dotnet add package IdentityServer4.AspNetIdentity
dotnet add package IdentityServer4.EntityFramework
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package Serilog.AspNetCore
dotnet add package VaultSharp
```

## 🔐 Production Checklist

- ✅ Signing Certificate (Vault oder Secret Volume)
- ✅ HTTPS/TLS aktiviert
- ✅ Secure Cookies enabled
- ✅ CORS für trusted Origins konfiguriert
- ✅ Rate Limiting aktiviert
- ✅ Logging & Monitoring (Serilog + Loki)
- ✅ Database Backups automatisieren
- ✅ Health Checks & Alerts

## 🔗 Referenzen

- [IdentityServer4 Docs](https://identityserver4.readthedocs.io/)
- [IdentityServer4 Repository](https://github.com/duendesoftware/IdentityServer4)
- [ASP.NET Core + Docker](https://docs.microsoft.com/en-us/dotnet/core/docker/build-container)
- [Duende (kommerzieller Nachfolger)](https://duendesoftware.com/)
