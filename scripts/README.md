# Certificate Management Scripts

## 📝 Overview

This directory contains certificate management scripts for the Shared Services platform.

## 🚀 Current Setup: Vault PKI

The platform now uses **HashiCorp Vault PKI Engine** (not Step CA).

**All documentation for certificate generation has moved to:**
👉 **[README_VAULT_PKI.md](./README_VAULT_PKI.md)**

## Quick Start

### Generate a Server Certificate

**Windows:**
```powershell
.\generate-certs-vault.ps1 -Domain "myapp.local"
```

**Linux/macOS:**
```bash
./generate-certs-vault.sh -d myapp.local
```

### Generate a Client Certificate

**Windows:**
```powershell
.\generate-certs-vault.ps1 -CommonName "client@example.com" -Role "client-cert"
```

**Linux/macOS:**
```bash
./generate-certs-vault.sh -c "client@example.com" -r client-cert
```

### Setup Keycloak Certificate (for Traefik HTTPS)

Use the same scripts as above. The certificate is automatically picked up by Traefik:

**Windows:**
```powershell
.\generate-certs-vault.ps1 -Domain "keycloak.local"
```

**Linux/macOS:**
```bash
./generate-certs-vault.sh -d keycloak.local
```

Then restart services: `docker compose up -d`

👉 **[../../KEYCLOAK_VAULT_HTTPS.md](../KEYCLOAK_VAULT_HTTPS.md)** - Full Keycloak HTTPS setup guide

## 📚 Documentation

- **[README_VAULT_PKI.md](./README_VAULT_PKI.md)** - Full Vault PKI documentation
- **[../PKI_SETUP_VAULT.md](../PKI_SETUP_VAULT.md)** - PKI initialization guide
- **[../VAULT_HTTPS_SETUP.md](../VAULT_HTTPS_SETUP.md)** - Traefik HTTPS setup

## 📜 Legacy Scripts

The following scripts are for legacy Step CA setup and are no longer actively maintained:
- `generate-certs.ps1` - Legacy Step CA (Windows)
- `generate-certs.sh` - Legacy Step CA (Linux)
- `rotate-certs.sh` - Legacy certificate rotation

**Use the Vault PKI scripts (`generate-certs-vault.ps1` / `generate-certs-vault.sh`) instead.**

## 🔄 Migration from Step CA

If you were using Step CA before, the transition to Vault PKI is straightforward:

1. **Old Way:** `./scripts/generate-certs.sh myapp.local`
2. **New Way:** `./scripts/generate-certs-vault.sh -d myapp.local`

The output files are compatible - same `.crt`, `.key`, and `root_ca.crt` structure.

