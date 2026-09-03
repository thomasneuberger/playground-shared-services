# playground-shared-services

Shared Services repository with a Docker Compose based platform for identity, messaging, secrets, and observability.

## Repository Overview

This repository provides a local/shared environment with:

- Keycloak for identity and access management
- RabbitMQ for messaging (AMQPS + HTTPS management)
- Vault for secrets and PKI-based certificate issuance
- Prometheus, Loki, Tempo, Grafana for metrics, logs, traces, and dashboards
- Traefik as HTTPS gateway (file-provider mode, no Docker socket dependency)

## Architecture

- Gateway entrypoint: `https://<service>.local:8443`
- Central routing config: `config/traefik/dynamic.yml`
- Static Traefik config: `config/traefik/traefik.yml`
- Compose orchestration: `docker-compose.yml`

Detailed architecture: [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md)

## Prerequisites

- Docker Desktop or Docker Engine
- Docker Compose v1.29+
- ~4 GB free RAM

## Quick Start

1. Adjust values in `.env` (passwords/tokens/host name).
2. Start the stack:

```bash
docker compose up -d
```

3. Verify status:

```bash
docker compose ps
```

4. Generate required certificates (example):

```powershell
.\scripts\generate-certs-vault.ps1 -Domain "traefik.local"
```

## Repository Structure

- `config/` service configurations (Traefik, Grafana provisioning, Loki, Prometheus, Tempo, Vault, RabbitMQ)
- `scripts/` operational and certificate management scripts
- `certs/` generated certificates and CA artifacts
- `doc/` full platform documentation

## Documentation Index

- Main guide: [doc/README.md](doc/README.md)
- Keycloak: [doc/keycloak/KEYCLOAK_SETUP.md](doc/keycloak/KEYCLOAK_SETUP.md)
- Keycloak HTTPS via Vault PKI: [doc/keycloak/KEYCLOAK_VAULT_HTTPS.md](doc/keycloak/KEYCLOAK_VAULT_HTTPS.md)
- Grafana HTTPS: [doc/grafana/GRAFANA_VAULT_HTTPS.md](doc/grafana/GRAFANA_VAULT_HTTPS.md)
- Prometheus HTTPS: [doc/prometheus/PROMETHEUS_VAULT_HTTPS.md](doc/prometheus/PROMETHEUS_VAULT_HTTPS.md)
- Loki HTTPS: [doc/loki/LOKI_VAULT_HTTPS.md](doc/loki/LOKI_VAULT_HTTPS.md)
- Tempo HTTPS: [doc/tempo/TEMPO_VAULT_HTTPS.md](doc/tempo/TEMPO_VAULT_HTTPS.md)
- Vault HTTPS setup: [doc/vault/VAULT_HTTPS_SETUP.md](doc/vault/VAULT_HTTPS_SETUP.md)
- Vault PKI setup: [doc/vault/PKI_SETUP_VAULT.md](doc/vault/PKI_SETUP_VAULT.md)
- Vault PKI migration: [doc/vault/VAULT_PKI_MIGRATION.md](doc/vault/VAULT_PKI_MIGRATION.md)
- Vault PKI scripts doc: [doc/vault/README_VAULT_PKI.md](doc/vault/README_VAULT_PKI.md)
- Script docs: [doc/scripts/README.md](doc/scripts/README.md)
- .NET integration: [doc/dotnet/DOTNET_INTEGRATION.md](doc/dotnet/DOTNET_INTEGRATION.md)
