# Architektur-Übersicht

## Gesamtarchitektur

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Shared Services Platform                             │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │          Docker Compose Netzwerk (shared-services)                 │ │
│  │                                                                    │ │
│  │  ┌─────────────────  AUTHENTICATION ─────────────────┐            │ │
│  │  │                                                   │            │ │
│  │  │  ┌────────────────────┐      ┌─────────────────┐ │            │ │
│  │  │  │                    │      │                 │ │            │ │
│  │  │  │  Keycloak         │◄────►│  PostgreSQL     │ │            │ │
│  │  │  │  (Port 8080)       │      │  (Keycloak DB)  │ │            │ │
│  │  │  │                    │      │                 │ │            │ │
│  │  │  └────────────────────┘      └─────────────────┘ │            │ │
│  │  │                                                   │            │ │
│  │  │  OpenID Connect / OAuth2 / SAML                  │            │ │
│  │  └───────────────────────────────────────────────────┘            │ │
│  │                                                                    │ │
│  │  ┌─────────────────── MESSAGING ───────────────┐                 │ │
│  │  │                                             │                 │ │
│  │  │  ┌──────────────────────────────────────┐  │                 │ │
│  │  │  │                                      │  │                 │ │
│  │  │  │  RabbitMQ                           │  │                 │ │
│  │  │  │  Queues & Topics (Port 5672)        │  │                 │ │
│  │  │  │  Management UI (Port 15672)         │  │                 │ │
│  │  │  │                                      │  │                 │ │
│  │  │  └──────────────────────────────────────┘  │                 │ │
│  │  │                                             │                 │ │
│  │  └─────────────────────────────────────────────┘                 │ │
│  │                                                                    │ │
│  │  ┌──────────────────── SECRETS ──────────────────┐               │ │
│  │  │                                               │               │ │
│  │  │  ┌──────────────────────────────────────────┐ │               │ │
│  │  │  │                                          │ │               │ │
│  │  │  │  HashiCorp Vault                        │ │               │ │
│  │  │  │  Secret Management (Port 8200)          │ │               │ │
│  │  │  │  - API Keys                             │ │               │ │
│  │  │  │  - DB Credentials                       │ │               │ │
│  │  │  │  - PKI Secrets                          │ │               │ │
│  │  │  │                                          │ │               │ │
│  │  │  └──────────────────────────────────────────┘ │               │ │
│  │  │                                               │               │ │
│  │  └───────────────────────────────────────────────┘               │ │
│  │                                                                    │ │
│  │  ┌────────────────── PKI / CERTS ──────────────────┐             │ │
│  │  │                                                  │             │ │
│  │  │  ┌────────────────────────────────────────────┐ │             │ │
│  │  │  │                                            │ │             │ │
│  │  │  │  Step CA (Smallstep)                      │ │             │ │
│  │  │  │  Certificate Authority (Port 9000)        │ │             │ │
│  │  │  │                                            │ │             │ │
│  │  │  │  ┌──────────────┐  ┌──────────────────┐  │ │             │ │
│  │  │  │  │ Root CA      │  │ Intermediate CA  │  │ │             │ │
│  │  │  │  │ (Self-signed)│  │ (für Ausstellung)│  │ │             │ │
│  │  │  │  └──────────────┘  └──────────────────┘  │ │             │ │
│  │  │  │                                            │ │             │ │
│  │  │  └────────────────────────────────────────────┘ │             │ │
│  │  │                                                  │             │ │
│  │  │  Server Certs: DigitalSignatures, TLS/HTTPS    │             │ │
│  │  │  Client Certs: mTLS, Service-to-Service        │             │ │
│  │  │                                                  │             │ │
│  │  └──────────────────────────────────────────────────┘             │ │
│  │                                                                    │ │
│  │  ┌──────────────────────────────────────────────────────────────┐ │ │
│  │  │              OBSERVABILITY / MONITORING                      │ │ │
│  │  │                                                              │ │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │ │ │
│  │  │  │ Prometheus   │  │    Loki      │  │  Tempo           │ │ │ │
│  │  │  │ (Metrics)    │  │ (Log Agg.)   │  │ (Distributed     │ │ │ │
│  │  │  │ Port 9090    │  │ Port 3100    │  │  Tracing)        │ │ │ │
│  │  │  │              │  │              │  │ Port 3200        │ │ │ │
│  │  │  │ - HTTP       │  │ - Loki Lang  │  │ - OTLP gRPC      │ │ │ │
│  │  │  │ - Scraping   │  │ - Filtering  │  │   (Port 4317)    │ │ │ │
│  │  │  │ - TS DB      │  │              │  │ - OTLP HTTP      │ │ │ │
│  │  │  │              │  │              │  │   (Port 4318)    │ │ │ │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────┘ │ │ │
│  │  │          │                │                   │             │ │ │
│  │  │          └────────────────┼───────────────────┘             │ │ │
│  │  │                           │                                 │ │ │
│  │  │                    ┌──────▼──────┐                         │ │ │
│  │  │                    │   Grafana    │                         │ │ │
│  │  │                    │ (Dashboard)  │                         │ │ │
│  │  │                    │ Port 3000    │                         │ │ │
│  │  │                    └──────────────┘                         │ │ │
│  │  │                                                              │ │ │
│  │  └──────────────────────────────────────────────────────────────┘ │ │
│  │                                                                    │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │          Client Applications (ASP.NET Core)                         │ │
│  │                                                                     │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │ │
│  │  │   MyApp 1    │  │   MyApp 2    │  │   MyApp 3    │             │ │
│  │  │ (Consumer A) │  │ (Consumer B) │  │ (Consumer C) │             │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘             │ │
│  │         │                 │                 │                      │ │
│  │         └─────────────────┼─────────────────┘                      │ │
│  │                           │                                        │ │
│  │              ┌────────────▼────────────┐                          │ │
│  │              │  OpenTelemetry + mTLS  │                          │ │
│  │              │  (Tracing, Metrics)    │                          │ │
│  │              └──────────────────────────┘                          │ │
│  │                                                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Communication Flows

### 1. Service Authentication Flow

```
┌─────────────┐                                           ┌──────────────┐
│             │                                           │              │
│  ASP.NET    │  1. Request Token                         │ Identity     │
│  App        │──────────────────────────────────────────►│ Server       │
│             │                                           │              │
│             │  2. Return JWT Token                      │              │
│             │◄──────────────────────────────────────────│              │
│             │                                           │              │
│             │  3. Include Token in Requests             │              │
│             │  (Authorization: Bearer <token>)          │              │
│             │                                           │              │
└─────────────┘                                           └──────────────┘
                          ▲
                          │
                ┌─────────┴─────────┐
                │                   │
              ┌─┴───┐             ┌─┴───┐
              │Vault│             │Cert │
              │(PWD)│             │(mTLS)
              └─────┘             └─────┘
```

### 2. Message Processing Flow

```
┌─────────────┐        ┌──────────────┐        ┌─────────────────┐
│             │        │              │        │                 │
│  Producer   │        │   RabbitMQ   │        │   Consumer      │
│   Service   │        │              │        │   Service       │
│             │        │  Exchange    │        │                 │
│             │        │  ↓           │        │                 │
│  Publishes  │───────►│  Queue       │───────►│  Processes      │
│  Message    │        │  ↓           │        │  Message        │
│             │        │  Topic       │        │                 │
│             │        │              │        │                 │
│             │        │ DLX (errors) │        │                 │
│             │        │              │        │                 │
└─────────────┘        └──────────────┘        └─────────────────┘
       │                                               │
       └──────────────────┬──────────────────────────┘
                          │
                 Logs to Loki + Traces
```

### 3. Secret Management Flow

```
┌─────────────┐                    ┌────────────┐
│             │                    │            │
│  App Start  │                    │   Vault    │
│             │                    │            │
│  Request    │                    │ KV Store   │
│  Secrets    │──────(Auth)───────►│            │
│             │                    │ - DB PWD   │
│             │                    │ - API KEY  │
│  Receive    │                    │ - TLS Cert │
│  Encrypted  │◄────(Response)─────│            │
│  Values     │                    │            │
│             │                    │            │
│  Decrypt &  │                    │            │
│  Cache in   │                    │            │
│  Memory     │                    │            │
│             │                    │            │
└─────────────┘                    └────────────┘
       │
       └─────(Use in Runtime)─────────┐
                                      ▼
                              [Database Connection /
                               API Authentication /
                               TLS Configuration]
```

### 4. PKI / Certificate Flow

```
┌────────────────────────────────────────────────────────────────┐
│                  Certificate Lifecycle                          │
│                                                                 │
│  Client Request                                                │
│  └─────────────────────────┐                                   │
│                            │                                   │
│                            ▼                                   │
│  ┌─────────────────────────────────────┐                      │
│  │  Step CA                            │                      │
│  │                                     │                      │
│  │  Validate Request                   │                      │
│  │  └──────────────────────────────────┘                      │
│  │           │                                                │
│  │           ├─ Root CA Signs Intermediate CA                │
│  │           │                                                │
│  │           └─ Issue Leaf Certificates (TLS/mTLS)           │
│  │                                                            │
│  └────────────────────────────────────────┘                  │
│                   │                                            │
│                   ▼                                            │
│  ┌──────────────────────────────┐                            │
│  │ Certificate Bundle           │                            │
│  │                              │                            │
│  │ - Server Certificate (PEM)   │ ──┐                        │
│  │ - Private Key (PEM)          │   ├─ Store in Volume      │
│  │ - Root CA Certificate (PEM)  │ ──┤ or Vault              │
│  │ - Chain of Trust             │   │                        │
│  │                              │ ──┘                        │
│  └──────────────────────────────┘                            │
│           │                                                   │
│           ▼                                                   │
│  ┌────────────────────────────────────────┐                  │
│  │ Application Configuration              │                  │
│  │                                        │                  │
│  │ ASPNETCORE Kestrel Settings:           │                  │
│  │ - Certificates:Default:Path            │                  │
│  │ - Certificates:Default:KeyPath         │                  │
│  │                                        │                  │
│  │ Client Validation:                     │                  │
│  │ - ClientCertificateMode                │                  │
│  │ - SSL Policy Errors                    │                  │
│  │ - Custom Validation Callback           │                  │
│  │                                        │                  │
│  └────────────────────────────────────────┘                  │
│           │                                                   │
│           ▼                                                   │
│  ┌────────────────────────────────────────┐                  │
│  │ Runtime                                │                  │
│  │                                        │                  │
│  │ HTTPS/TLS Communication Active         │                  │
│  │ Certificate Validation Ongoing         │                  │
│  │ Expiry Monitoring via Health Checks    │                  │
│  │                                        │                  │
│  └────────────────────────────────────────┘                  │
│           │                                                   │
│           └─ Rotation Check (30-60 days before expiry)       │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

### 5. Observability / Monitoring Flow

```
┌──────────────────────────────────────────────────────────────┐
│                   Observability Stack                         │
│                                                               │
│  Applications (OpenTelemetry Instrumentation)                │
│  │                                                            │
│  ├─ Traces ───────────────────►  TEMPO                       │
│  │                              (Distributed Tracing)        │
│  │                                                            │
│  ├─ Metrics ──────────────────►  PROMETHEUS                  │
│  │  (HTTP /metrics endpoints)   (Time Series DB)             │
│  │                                                            │
│  └─ Logs ─────────────────────►  LOKI                        │
│     (Structured Logging)        (Log Aggregation)            │
│                                                               │
│           ▲       ▲       ▲                                   │
│           │       │       │                                   │
│           └───────┼───────┘                                   │
│                   │                                           │
│                   ▼                                           │
│           ┌───────────────┐                                   │
│           │    GRAFANA    │                                   │
│           │               │                                   │
│           │ - Dashboards  │                                   │
│           │ - Alerts      │                                   │
│           │ - Annotations │                                   │
│           │ - Correlate   │                                   │
│           │   T+M+L       │                                   │
│           │               │                                   │
│           └───────────────┘                                   │
│                   │                                           │
│                   ▼                                           │
│           [Operations Team]                                   │
│           [Monitoring & Alerting]                             │
│           [Performance Analysis]                              │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Data Flow Summary

1. **Authentication**: Apps → Keycloak (OpenID Connect/OAuth2/SAML) ✓
2. **Secrets**: Apps → Vault (encrypted credentials) ✓
3. **Messaging**: App A → RabbitMQ → App B (async communication) ✓
4. **Certificates**: Vault PKI → Apps (HTTPS/mTLS) ✓
5. **Observability**: Apps → Prometheus/Loki/Tempo → Grafana (insights) ✓

## Port Mapping Summary

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Keycloak | 8080 | HTTP | OpenID Connect/OAuth2/SAML Server |
| RabbitMQ AMQP | 5672 | TCP | Message Broker |
| RabbitMQ UI | 15672 | HTTP | Management Console |
| Vault | 8200 | HTTP | Secret Management & PKI |
| Prometheus | 9090 | HTTP | Metrics DB |
| Loki | 3100 | HTTP | Log Aggregation |
| Tempo | 3200 | HTTP | Tracing Backend |
| Tempo OTLP gRPC | 4317 | gRPC | Trace Collection |
| Tempo OTLP HTTP | 4318 | HTTP | Trace Collection |
| Grafana | 3000 | HTTP | Dashboards |
| PostgreSQL (Keycloak) | 5432 | TCP | Keycloak DB (internal) |

## Network Isolation

Alle Services laufen im `shared-services` Docker Netzwerk und kommunizieren intern über Container-Namen:
- `keycloak:8080`
- `keycloak-db:5432`
- `rabbitmq:5672`
- `vault:8200`
- `prometheus:9090`
- `loki:3100`
- `tempo:3200`
- `grafana:3000`

Client-Applications könnten über das Host-System oder ein separates Netzwerk verbunden werden.
