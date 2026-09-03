# Microsoft Entra ID als Identity Provider für Realm `playground`

Diese Anleitung beschreibt, wie du Microsoft Entra ID (Azure AD) als externen Identity Provider für Keycloak im Realm `playground` nutzt.

Die technische Konfiguration ist bereits im Realm-Import enthalten:

- `config/keycloak/playground-realm.json`
- Identity Provider Alias: `entraid`
- Lokale User-Anlage bei erstem Login: aktiviert
- Account Linking: aktiviert (`linkOnly=false`, First Broker Login Flow)

## Voraussetzungen

- Keycloak läuft über Traefik unter `https://keycloak.local:8443`
- Realm Import ist aktiv (`--import-realm`)
- Du hast Zugriff auf ein Entra ID Tenant (Microsoft Azure Portal)

## 1) App Registration in Entra ID erstellen

1. Azure Portal → **Microsoft Entra ID** → **App registrations** → **New registration**
2. Name z. B. `keycloak-playground-broker`
3. Supported account types nach Bedarf wählen
4. Redirect URI (Web) setzen:

   ```
   https://keycloak.local:8443/realms/playground/broker/entraid/endpoint
   ```

5. Registrierung speichern

## 2) Client Secret in Entra ID erzeugen

1. App registration → **Certificates & secrets**
2. **New client secret** erstellen
3. Secret-Wert direkt kopieren (wird nur einmal angezeigt)

## 3) Benötigte Werte in `.env` setzen

Ergänze folgende Variablen in deiner `.env`:

```env
# Entra ID (Keycloak Identity Provider)
KEYCLOAK_ENTRA_ID_TENANT_ID=<tenant-id-guid>
KEYCLOAK_ENTRA_ID_CLIENT_ID=<application-client-id-guid>
KEYCLOAK_ENTRA_ID_CLIENT_SECRET=<entra-client-secret>
```

## 4) Keycloak Realm Import anwenden

Wichtig: Startup-Import (`--import-realm`) importiert nur neue Realms. Existiert `playground` bereits, wird der Import übersprungen.

### Option A: Neuaufbau (einfach für Dev/Test)

1. Keycloak/DB Daten löschen (nur wenn gewünscht)
2. Stack neu starten:

```bash
docker compose up -d
```

### Option B: Bestehenden Realm manuell ergänzen

Wenn der Realm bereits produktiv genutzt wird, füge den IdP im Keycloak Admin UI hinzu und nutze dieselben Werte wie im Importfile.

## 5) Login testen

1. Öffne:

   ```
   https://keycloak.local:8443/realms/playground/account
   ```

2. Wähle **Microsoft Entra ID**
3. Melde dich mit einem Entra User an

Erwartetes Verhalten:

- Beim ersten Login wird ein lokaler Keycloak-User erstellt
- Bestehende Accounts können über den First Broker Login Flow verknüpft werden

## Hinweise zu User-Anlage und Linking

- `updateProfileFirstLoginMode: on` fordert ggf. Profilergänzung beim Erstlogin
- `trustEmail: true` erlaubt E-Mail-basiertes Linking zuverlässiger, wenn Entra verifizierte E-Mails liefert
- Account Linking hängt von den Matching-Regeln des First Broker Login Flows ab (standardmäßig aktiv)

## Zusammenspiel mit Traefik Dashboard Auth

Für das Traefik Dashboard ist zusätzlich Gruppenmitgliedschaft erforderlich:

- Keycloak Gruppe: `/traefik-dashboard-access`
- `oauth2-proxy` filtert mit `OAUTH2_PROXY_ALLOWED_GROUPS=/traefik-dashboard-access`

Das bedeutet:

- Entra ID Login allein reicht nicht
- Der (lokale/brokered) User muss in Keycloak der Gruppe `/traefik-dashboard-access` zugeordnet sein
