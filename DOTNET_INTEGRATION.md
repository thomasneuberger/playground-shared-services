# Integration Guide für ASP.NET Core Anwendungen

## 🔐 Keycloak Integration (OpenID Connect)

### Installation

```bash
dotnet add package Microsoft.AspNetCore.Authentication.OpenIdConnect
dotnet add package System.IdentityModel.Tokens.Jwt
```

### Configuration in appsettings.json

```json
{
  "Keycloak": {
    "Realm": "myapp",
    "Authority": "http://keycloak:8080/realms/myapp",
    "ClientId": "myapp-api",
    "ClientSecret": "your-client-secret-here"
  }
}
```

### Program.cs Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

var keycloakSettings = builder.Configuration.GetSection("Keycloak");

// OpenID Connect Authentication
builder.Services.AddAuthentication(options =>
{
    options.DefaultScheme = "Cookies";
    options.DefaultChallengeScheme = "oidc";
})
.AddCookie("Cookies")
.AddOpenIdConnect("oidc", options =>
{
    options.Authority = keycloakSettings["Authority"];
    options.ClientId = keycloakSettings["ClientId"];
    options.ClientSecret = keycloakSettings["ClientSecret"];
    
    options.ResponseType = "code";
    options.SaveTokens = true;
    
    options.Scope.Add("openid");
    options.Scope.Add("profile");
    options.Scope.Add("email");
    
    // Token Validation
    options.TokenValidationParameters = new TokenValidationParameters
    {
        NameClaimType = "preferred_username",
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
        var username = User.FindFirst("preferred_username")?.Value;
        
        return Ok(new { userId, username });
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
public class KeycloakTokenService
{
    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    
    public KeycloakTokenService(HttpClient httpClient, IConfiguration configuration)
    {
        _httpClient = httpClient;
        _configuration = configuration;
    }
    
    public async Task<string> GetTokenAsync()
    {
        var keycloak = _configuration.GetSection("Keycloak");
        var realm = keycloak["Realm"];
        var authority = keycloak["Authority"];
        var clientId = keycloak["ClientId"];
        var clientSecret = keycloak["ClientSecret"];
        
        var request = new HttpRequestMessage(HttpMethod.Post,
            $"{authority.Replace($"/realms/{realm}", "")}/realms/{realm}/protocol/openid-connect/token")
        {
            Content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("grant_type", "client_credentials"),
                new KeyValuePair<string, string>("client_id", clientId),
                new KeyValuePair<string, string>("client_secret", clientSecret),
            })
        };
        
        var response = await _httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        
        var json = await response.Content.ReadAsAsync<JsonElement>();
        return json.GetProperty("access_token").GetString();
    }
}

// Registration
builder.Services.AddHttpClient<KeycloakTokenService>();

// Usage
public class SecureServiceClient
{
    private readonly HttpClient _httpClient;
    private readonly KeycloakTokenService _tokenService;
    
    public SecureServiceClient(HttpClient httpClient, KeycloakTokenService tokenService)
    {
        _httpClient = httpClient;
        _tokenService = tokenService;
    }
    
    public async Task<string> CallServiceAsync()
    {
        var token = await _tokenService.GetTokenAsync();
        
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

---

## 🔐 Vault Integration

### Installation

```bash
dotnet add package VaultSharp
```

### Configuration in appsettings.json

```json
{
  "Vault": {
    "Address": "http://localhost:8200",
    "Token": "myroot123",
    "SecretsPath": "secret/myapp"
  }
}
```

### Extension zur Registrierung

```csharp
// Extensions/ServiceCollectionExtensions.cs

public static IServiceCollection AddVaultConfiguration(
    this IServiceCollection services, 
    IConfiguration configuration)
{
    var vaultAddress = configuration["Vault:Address"];
    var vaultToken = configuration["Vault:Token"];
    var secretsPath = configuration["Vault:SecretsPath"];

    var authMethod = new TokenAuthMethodInfo(vaultToken);
    var vaultClientSettings = new VaultClientSettings(vaultAddress, authMethod);
    var vaultClient = new VaultClient(vaultClientSettings);

    services.AddSingleton(vaultClient);
    return services;
}
```

### Usage in Services

```csharp
public class DatabaseService
{
    private readonly IVaultClient _vaultClient;

    public DatabaseService(IVaultClient vaultClient)
    {
        _vaultClient = vaultClient;
    }

    public async Task<string> GetConnectionStringAsync()
    {
        var secret = await _vaultClient.V1.Secrets.KeyValue.V2
            .ReadSecretAsync(path: "database");
        
        var username = secret.Data.Data["username"].ToString();
        var password = secret.Data.Data["password"].ToString();
        
        return $"Server=localhost;User Id={username};Password={password};";
    }
}
```

---

## 🔄 RabbitMQ Integration

### Installation

```bash
dotnet add package RabbitMQ.Client
```

### RabbitMQ Service

```csharp
public interface IMessageBroker
{
    Task PublishAsync<T>(string queue, T message);
    Task SubscribeAsync<T>(string queue, Func<T, Task> handler);
}

public class RabbitMQBroker : IMessageBroker
{
    private readonly IConnection _connection;
    
    public RabbitMQBroker(IConfiguration configuration)
    {
        var factory = new ConnectionFactory
        {
            HostName = configuration["RabbitMQ:HostName"] ?? "localhost",
            UserName = configuration["RabbitMQ:Username"] ?? "guest",
            Password = configuration["RabbitMQ:Password"] ?? "guest"
        };
        
        _connection = factory.CreateConnection();
    }

    public async Task PublishAsync<T>(string queue, T message)
    {
        using var channel = _connection.CreateModel();
        channel.QueueDeclare(
            queue: queue,
            durable: true,
            exclusive: false,
            autoDelete: false);

        var json = JsonSerializer.Serialize(message);
        var body = Encoding.UTF8.GetBytes(json);

        channel.BasicPublish(
            exchange: "",
            routingKey: queue,
            basicProperties: null,
            body: body);
    }

    public async Task SubscribeAsync<T>(string queue, Func<T, Task> handler)
    {
        using var channel = _connection.CreateModel();
        channel.QueueDeclare(
            queue: queue,
            durable: true,
            exclusive: false,
            autoDelete: false);

        var consumer = new EventingBasicConsumer(channel);
        consumer.Received += async (model, ea) =>
        {
            var body = ea.Body.ToArray();
            var json = Encoding.UTF8.GetString(body);
            var message = JsonSerializer.Deserialize<T>(json);
            
            await handler(message);
            channel.BasicAck(ea.DeliveryTag, false);
        };

        channel.BasicConsume(queue: queue, autoAck: false, consumer: consumer);
    }
}
```

### Registration in Program.cs

```csharp
builder.Services.AddSingleton<IMessageBroker, RabbitMQBroker>();
```

---

## 📊 OpenTelemetry Integration

### Installation

```bash
dotnet add package OpenTelemetry
dotnet add package OpenTelemetry.Exporter.Otlp
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Instrumentation.Http
dotnet add package OpenTelemetry.Exporter.Prometheus
```

### Configuration in Program.cs

```csharp
var builder = WebApplication.CreateBuilder(args);

// OpenTelemetry Setup
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(opt => opt.Endpoint = new Uri("http://localhost:4317")))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddPrometheusExporter());

var app = builder.Build();

// Prometheus Metrics Endpoint
app.MapPrometheusScrapingEndpoint();

app.Run();
```

### Custom Activities (Traces)

```csharp
using var activity = new System.Diagnostics.Activity("ProcessOrder")
    .SetTag("order.id", orderId)
    .Start();

try
{
    // Business Logic
}
catch (Exception ex)
{
    activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
    throw;
}
finally
{
    activity?.Dispose();
}
```

---

## � Hinweis: Verwende Keycloak für Authentifizierung

IdentityServer wurde durch Keycloak ersetzt. Siehe [Keycloak Integration](#-keycloak-integration-openid-connect) oben und [KEYCLOAK_SETUP.md](KEYCLOAK_SETUP.md) für vollständige Anweisungen.

---

## 📨 appsettings.json Beispiel

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning"
    }
  },
  "Keycloak": {
    "Realm": "myapp",
    "Authority": "http://keycloak:8080/realms/myapp",
    "ClientId": "myapp-api",
    "ClientSecret": "your-client-secret"
  },
    "ClientSecret": "secret"
  },
  "RabbitMQ": {
    "HostName": "localhost",
    "Username": "guest",
    "Password": "guest"
  },
  "Vault": {
    "Address": "http://localhost:8200",
    "Token": "myroot123",
    "SecretsPath": "secret/data/myapp"
  },
  "OpenTelemetry": {
    "OtlpEndpoint": "http://localhost:4317"
  }
}
```

---

## 🔐 HTTPS und Zertifikate (Vault PKI)

### Installation

```bash
dotnet add package System.Security.Cryptography.X509Certificates
```

### HTTPS Server mit Vault PKI Zertifikat

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel((context, options) =>
{
    // HTTPS mit Zertifikat von Vault PKI
    options.ListenAnyIP(5001, listenOptions =>
    {
        listenOptions.UseHttps(
            certificatePath: "/app/certs/server.crt",
            keyPath: "/app/certs/server.key"
        );
    });
    
    // HTTP für Entwicklung (optional)
    if (context.HostingEnvironment.IsDevelopment())
    {
        options.ListenAnyIP(5000);
    }
});

var app = builder.Build();
app.Run();
```

### Certificate automatisch aus Vault PKI laden

```csharp
// Extensions/CertificateExtensions.cs
public static IWebHostBuilder UseVaultPkiCertificate(
    this IWebHostBuilder webHost)
{
    return webHost.ConfigureKestrel((context, options) =>
    {
        var certPath = context.Configuration["Certificates:Path"];
        var keyPath = context.Configuration["Certificates:KeyPath"];
        
        if (File.Exists(certPath) && File.Exists(keyPath))
        {
            options.ListenAnyIP(5001, listenOptions =>
            {
                listenOptions.UseHttps(certPath, keyPath);
            });
        }
    });
}

// Program.cs
builder.WebHost.UseVaultPkiCertificate();
```

---

## 🔐 Mutual TLS (mTLS) - Client Authentifizierung

### Server: Client-Zertifikat validieren

```csharp
// Program.cs
builder.WebHost.ConfigureKestrel((context, options) =>
{
    options.ListenAnyIP(5001, listenOptions =>
    {
        listenOptions.UseHttps(serverCertPath, serverKeyPath);
        
        // Client-Zertifikat erforderlich
        listenOptions.ClientCertificateMode = 
            ClientCertificateMode.RequireCertificate;
    });
});

var app = builder.Build();

// Middleware zur Client-Zertifikat-Validierung
app.Use(async (context, next) =>
{
    var clientCert = context.Connection.ClientCertificate;
    
    if (clientCert == null)
    {
        context.Response.StatusCode = 401;
        await context.Response.WriteAsync("Client certificate required");
        return;
    }
    
    // Zusätzliche Validierung
    try
    {
        var x509Cert = new X509Certificate2(clientCert);
        
        // CN überprüfen (z.B. "client@example.com")
        var subject = x509Cert.Subject;
        
        // Chain Validierung mit Root CA
        var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
        chain.ChainPolicy.TrustAnchors.Add(new X509Certificate2("/app/certs/root_ca.crt"));
        
        if (!chain.Build(x509Cert))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsync("Certificate validation failed");
            return;
        }
        
        context.Items["ClientCertificate"] = x509Cert;
        context.Items["ClientName"] = subject;
    }
    catch (Exception ex)
    {
        context.Response.StatusCode = 401;
        await context.Response.WriteAsync($"Certificate error: {ex.Message}");
        return;
    }
    
    await next();
});

app.MapGet("/api/secure", (HttpContext context) =>
{
    var clientName = context.Items["ClientName"]?.ToString() ?? "Unknown";
    return Results.Ok(new { message = $"Hello {clientName}" });
});

app.Run();
```

### Client: mTLS Request mit eigenem Zertifikat

```csharp
// HttpClient mit Client-Zertifikat
var handler = new HttpClientHandler();
var clientCert = new X509Certificate2(
    "/app/certs/client.pfx",
    "password" // Falls mit Passwort geschützt
);
handler.ClientCertificates.Add(clientCert);

// Root CA für Server-Validierung
var rootCert = new X509Certificate2("/app/certs/root_ca.crt");
var certStore = new X509Store(StoreName.Root, StoreLocation.CurrentUser);
certStore.Open(OpenFlags.ReadWrite);
certStore.Add(rootCert);
certStore.Close();

var httpClient = new HttpClient(handler)
{
    BaseAddress = new Uri("https://api.myapp.local:5001")
};

var response = await httpClient.GetAsync("/api/secure");
var content = await response.Content.ReadAsStringAsync();
```

### Service Extension für mTLS

```csharp
// Extensions/MutualTlsExtensions.cs
public static IHttpClientBuilder AddMutualTls(
    this IHttpClientBuilder builder,
    string clientCertPath,
    string rootCaPath)
{
    return builder.ConfigureHttpClient((httpClient) =>
    {
        httpClient.DefaultRequestVersion = HttpVersion.Version20;
    })
    .ConfigureHttpMessageHandlerBuilder((handlerBuilder) =>
    {
        var handler = new HttpClientHandler();
        
        // Client certificate
        if (File.Exists(clientCertPath))
        {
            var clientCert = new X509Certificate2(clientCertPath);
            handler.ClientCertificates.Add(clientCert);
        }
        
        // Server validation mit Root CA
        if (File.Exists(rootCaPath))
        {
            var rootCert = new X509Certificate2(rootCaPath);
            var chain = new X509Chain();
            chain.ChainPolicy.ExtraStore.Add(rootCert);
            
            handler.ServerCertificateCustomValidationCallback = 
                (message, cert, chain2, errors) =>
            {
                // Root CA registrieren
                chain.ChainPolicy.TrustAnchors.Clear();
                chain.ChainPolicy.TrustAnchors.Add(rootCert);
                
                return chain.Build(new X509Certificate2(cert));
            };
        }
        
        handlerBuilder.PrimaryHandler = handler;
    });
}

// Program.cs
builder.Services.AddHttpClient("SecureApi")
    .AddMutualTls(
        clientCertPath: "/app/certs/client.crt",
        rootCaPath: "/app/certs/root_ca.crt"
    );
```

### Zertifikat-Pinning (zusätzliche Sicherheit)

```csharp
public static IHttpClientBuilder AddCertificatePinning(
    this IHttpClientBuilder builder,
    string expectedThumbprint)
{
    return builder.ConfigureHttpMessageHandlerBuilder((handlerBuilder) =>
    {
        var handler = new HttpClientHandler();
        
        handler.ServerCertificateCustomValidationCallback = 
            (message, cert, chain, errors) =>
        {
            var x509Cert = new X509Certificate2(cert);
            
            // Thumbprint überprüfen
            if (x509Cert.Thumbprint.Equals(expectedThumbprint, 
                StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
            
            return false;
        };
        
        handlerBuilder.PrimaryHandler = handler;
    });
}

// Verwendung
builder.Services.AddHttpClient("PinnedApi")
    .AddCertificatePinning("YOUR_EXPECTED_THUMBPRINT");
```

---

## 🚀 Health Checks ausführen

```csharp
builder.Services.AddHealthChecks()
    .AddCheck<VaultHealthCheck>("vault")
    .AddCheck<RabbitMQHealthCheck>("rabbitmq")
    .AddCheck<CertificateHealthCheck>("certificates");

public class CertificateHealthCheck : IHealthCheck
{
    private readonly ILogger<CertificateHealthCheck> _logger;
    
    public CertificateHealthCheck(ILogger<CertificateHealthCheck> logger)
    {
        _logger = logger;
    }
    
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var serverCert = new X509Certificate2("/app/certs/server.crt");
            
            if (serverCert.NotAfter < DateTime.UtcNow.AddDays(30))
            {
                _logger.LogWarning("Certificate expires soon: {NotAfter}",
                    serverCert.NotAfter);
                return HealthCheckResult.Degraded(
                    "Certificate expires in less than 30 days");
            }
            
            return HealthCheckResult.Healthy("Certificate valid");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy(
                "Certificate check failed", ex);
        }
    }
}

app.MapHealthChecks("/health");
```

---

## Deployment Tipps

1. **Secrets nie hart codieren** - Immer Vault verwenden
2. **Zertifikat-Rotation automatisieren** - Cron Job oder Kubernetes CronJob
3. **mTLS für Service-to-Service Kommunikation** verwenden
4. **Certificate Pinning** bei kritischen APIs
5. **Root CA offline speichern** - Intermediate CA für Tagesgeschäft
6. **Circuit Breaker** für externe Services (RabbitMQ, Vault)
7. **Retry-Policies** für asynchrone Operationen
8. **Regelmäßige Health Checks** durchführen (Zertifikat-Ablauf!)
9. **Monitoring & Alerting** in Grafana konfigurieren

