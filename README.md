# RCV Ganesha

**Ganesha** is a **vehicle and driver compliance tracker** that you host yourself. It answers two
questions for HR and fleet supervisors: who drives which work truck, and whether the things
that must stay current (insurance cards, registration, driver's licences, inspections, fuel
and ferry cards, parking passes) actually are. Maintenance and work orders are out of scope.

- **Vehicles and drivers**: unit number, body type, VIN (with an optional NHTSA vPIC
  lookup), plate, status and photo; primary and additional drivers with assignment history.
- **Records with expiry tracking**: admin-defined record types with a warning window,
  required and required-for-role flags, renewals that keep history, attachments, and a
  derived status (`ok`, `expiring`, `expired`, `missing`) shown the same way everywhere.
- **Cards and passes as assets**: gas, ferry, parking and similar cards, each with a holder,
  assignment history, status (`active`, `lost`, `retired`) and an image.
- **Microsoft 365 staff directory and Entra / OIDC sign-in**: people and photos come from
  Microsoft Graph and nobody is ever deleted (people who leave are disabled, keeping their
  history). Sign in locally, with Entra ID, or with Authentik; directory groups can map to
  roles.
- **Geotab sync**: devices are matched to vehicles by VIN, serial and plate, and odometer,
  engine hours and current driver are recorded. A manual value always wins over the Geotab
  value and can be reset. Optional write-back to Geotab is off by default, behind a master
  switch and per-field flags, with a dry run.
- **Smart upload**: a photo or PDF is read by a **pluggable Document AI provider** (Azure
  Document Intelligence, Anthropic, or any OpenAI-compatible endpoint such as Ollama, or none)
  and suggests where it belongs. A person confirms every suggestion; nothing is written
  without it.
- **Local-only licence verification**: a driver's licence is never sent to any remote
  provider. It is checked in memory by the app itself (barcode plus offline OCR), and **no
  licence image, licence number, date of birth or address is stored**.
- **CDL attestation**: vehicles can require a CDL; HR attests that the paper copy is on file.
- **Alerts and reminders** by **email** and **Microsoft Teams**, an expiry digest, and a
  bell in the top bar.
- **Roles**: `driver`, `supervisor`, `hr` and `admin`, held as assignments (a person can hold
  several). HR sees **sensitive documents** that supervisors only see the status of.
- **Audit log**, **reports** (compliance, expiring, assets, vehicles, drivers; JSON or CSV),
  **branding** (name, colours, logo, favicon, banner, login message) and themes (Light,
  Dark, Hacker, Auto).

One Docker image plus Postgres.

## License

**RCV Community License 1.1**: free for personal and home-lab use and for any organization's
own internal operations. A paid commercial license is required only to offer the software to
third parties as a hosted, managed, or SaaS service. See [`LICENSE`](LICENSE). Commercial
inquiries: **legal@rootchainventures.com**.

## Requirements

- **Docker** path (single host): Docker Engine and Docker Compose **2.24 or newer**. The
  compose file runs its own Postgres 17.
- **Kubernetes** path: a cluster, a Postgres server (14 or newer) you already run, an
  ingress controller that terminates TLS, and a volume. The 3-node HA overlay needs a
  `ReadWriteMany` storage class.
- A DNS name and a TLS certificate. Ganesha serves plain HTTP and expects a **reverse proxy
  or ingress to terminate TLS** in front of it.

The image is published on GHCR as `ghcr.io/root-chain-ventures-llc/ganesha` (built from a
private source repository; the source is not published) and can be pulled without logging
in. Source code is not published here; see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Quick start with `install.sh`

```bash
git clone https://github.com/Root-Chain-Ventures-LLC/RCV-Ganesha.git
cd RCV-Ganesha
./install.sh
```

`install.sh` creates `.env` from `.env.example` if it is missing, generates
`GANESHA_SECRET_KEY` and `GANESHA_DB_PASSWORD` with `openssl rand` when they are empty (it
never prints them), pulls the published image, starts the stack, waits for
`/api/health`, and prints the URL and the first-run step. It is safe to re-run: an existing
`.env` is kept and only empty secrets are filled in.

To set configuration up front, copy `.env.example` to `.env` and edit it before running
`./install.sh`; your values are preserved. **Set `BASE_URL` to the real `https://` address
first**: the app refuses to start on an `http://` one (see
[Configuration](#configuration)). For a local trial over plain http, set
`BASE_URL=http://localhost:8080` and `ALLOW_INSECURE_HTTP=true`.

**First run.** Open `<BASE_URL>/setup` and create the first administrator. Setup is open
only until the first person exists. If the host can be reached by others before you finish,
set `SETUP_TOKEN` in `.env` first: the setup page then asks for it. Every later sign-in
needs at least one active role assignment. Everything else (directory, SSO, Geotab,
Document AI, email, branding) is then configured under **Settings** by an administrator.

## Quick start with Docker Compose by hand

```bash
git clone https://github.com/Root-Chain-Ventures-LLC/RCV-Ganesha.git
cd RCV-Ganesha
cp .env.example .env
# edit .env: set GANESHA_SECRET_KEY (openssl rand -hex 32), GANESHA_DB_PASSWORD
# (openssl rand -hex 24) and BASE_URL
docker compose pull
docker compose up -d
curl http://127.0.0.1:8080/api/health
```

This starts Postgres (`db`, published on loopback only, volume `ganesha-pg`) and the app
(`app`, port 8080, volume `ganesha-data` for uploads, photos and attachments). Pin a
release with `GANESHA_VERSION=0.1.0` in `.env` (the default is the version this
`docker-compose.yml` shipped with).

Behind a reverse proxy on the same host set `GANESHA_BIND=127.0.0.1` so the app is reachable
only through the proxy, and set `TRUST_PROXY` (see below). The app container runs with a
read-only root filesystem, all capabilities dropped, `no-new-privileges`, and memory and
process limits.

---

## Kubernetes

Manifests live in [`deploy/k8s/`](deploy/k8s/): plain YAML with Kustomize, no Helm. Two
shapes:

- **Single replica (default):** `kubectl apply -k deploy/k8s`: one pod, a `ReadWriteOnce`
  volume, `strategy: Recreate`.
- **HA on 3 nodes:** `kubectl apply -k deploy/k8s/overlays/ha`: 3 replicas spread across
  nodes, a `ReadWriteMany` volume, rolling updates with no gap, and a PodDisruptionBudget.
  Needs a storage class that provides RWX (NFS, CephFS, Longhorn).

Kubernetes does not bundle a database: Ganesha uses a Postgres server you already run, one
database and one role per app (`deploy/k8s/create-db.sql` creates them). The short version:

```bash
kubectl create namespace ganesha
kubectl -n ganesha create secret generic ganesha \
  --from-literal=DATABASE_URL="postgres://ganesha:<password>@<postgres-host>:5432/ganesha" \
  --from-literal=GANESHA_SECRET_KEY="$(openssl rand -base64 32)"
# edit base/configmap.yaml (BASE_URL), base/ingress.yaml (host, TLS), base/pvc.yaml first
kubectl apply -k deploy/k8s
```

The image tag in the manifests is pinned to `0.1.0`. See
[`deploy/k8s/README.md`](deploy/k8s/README.md) for the full walkthrough, what the HA
overlay changes and why, upgrading, and troubleshooting.

---

## Configuration

Set these in `.env` (Docker Compose) or the ConfigMap/Secret (Kubernetes). Everything not
listed, including the Microsoft 365 directory, SSO, Geotab, Document AI, email and Teams
settings, is configured in the app under **Settings** by an administrator and stored in the
database. Those credentials are **never** environment variables.

| Variable | Required | Default | Notes |
|---|:---:|---|---|
| `GANESHA_SECRET_KEY` | yes | none | Master key (32 bytes, base64 or 64 hex characters; `openssl rand -hex 32`) that encrypts every credential saved in Settings. The image refuses to start without it. **Back it up.** |
| `GANESHA_SECRET_KEY_FILE` | no | none | Path to a file holding the same value, for Docker/Kubernetes secret mounts. |
| `GANESHA_SECRET_KEY_PREVIOUS` | no | none | Comma-separated former keys, kept readable during a key rotation. |
| `GANESHA_DB_PASSWORD` | yes (Compose) | none | Password for the bundled Postgres; letters and digits only. |
| `DATABASE_URL` | yes (Kubernetes) | built by Compose | Postgres connection string. Compose builds it for the bundled database. |
| `BASE_URL` | yes | none | The public URL people type, exactly. **Must be `https://`** or the app refuses to start (unless `ALLOW_INSECURE_HTTP=true`). Drives the `Secure` cookie flag, HSTS, the same-origin check on writes, and links in email. |
| `ALLOW_INSECURE_HTTP` | no | `false` | Allow an `http://` `BASE_URL`. Local trial only; never on an internet-facing deployment. |
| `TRUST_PROXY` | no | `false` | Whether to trust `X-Forwarded-*`. A hop count (`1` = one proxy; `2` behind a cloud load balancer plus a proxy), a comma-separated list of proxy IPs or CIDRs (strongest), or `true` (every hop; a client reaching the app directly can then spoof its IP). Leave `false` with no proxy. |
| `SETUP_TOKEN` | no | none | When set, creating the first administrator also needs this value. |
| `GANESHA_BIND`, `GANESHA_PORT` | no | `0.0.0.0`, `8080` | Compose only: host interface and port that publish the app. Use `GANESHA_BIND=127.0.0.1` behind a proxy on the same host. |
| `GANESHA_VERSION` | no | `0.1.0` | Compose only: the image tag to run. |
| `GANESHA_DB_PORT` | no | `5434` | Compose only: loopback port for the bundled Postgres. |
| `GANESHA_MEM_LIMIT`, `GANESHA_PIDS_LIMIT` | no | `1g`, `256` | Compose only: memory and process limits for the app container. |
| `ALLOW_PRIVATE_OUTBOUND` | no | `false` | Loopback, link-local and cloud-metadata destinations are always refused for Document AI, the OIDC issuer, SMTP and the Teams webhook. Private ranges (RFC 1918, CGNAT, unique-local) are refused too unless this is `true`; an on-premises model, a LAN mail relay or an internal identity provider needs it. |
| `UPLOAD_RATE_PER_HOUR` | no | `30` | Uploads per person per hour across every upload route. |
| `MAX_IMAGE_MEGAPIXELS` | no | `40` | Larger images are refused before decoding. PDFs render at most 10 pages. |
| `IMAGE_DECODE_TIMEOUT_MS` | no | `20000` | Stop waiting for a stuck image or PDF decode. |
| `SESSION_IDLE_TIMEOUT_HOURS`, `SESSION_ABSOLUTE_DAYS`, `MAX_SESSIONS_PER_PERSON` | no | `12`, `7`, `10` | Sliding idle timeout, absolute lifetime, and concurrent sessions per person (the oldest is dropped). |
| `PG_POOL_MAX` | no | `10` | Maximum Postgres connections the app opens. |
| `DOCAI_FETCH_TIMEOUT_MS`, `GEOTAB_FETCH_TIMEOUT_MS` | no | `60000`, `30000` | Timeouts for Document AI and Geotab requests. |

---

## Setting up the integrations

All of this is under **Settings** (administrators only) once the app is running.

**Microsoft 365 directory sync** (reads the staff directory through Microsoft Graph with
client credentials):

1. Entra admin center, App registrations, New registration (single tenant, no redirect URI).
2. API permissions, Microsoft Graph, **Application** permissions: `User.Read.All` (add
   `GroupMember.Read.All` if you scope the sync to one group), then grant admin consent.
3. Certificates and secrets: create a client secret. Copy the tenant ID and client ID.
4. **Settings, Directory**: enter them, choose the sync interval, enable, **Test**, then
   **Sync now**.

**Entra ID / OIDC sign-in:**

1. Register an app (or reuse the one above) with platform **Web** and the redirect URI
   `{BASE_URL}/api/auth/oidc/callback` (exactly, matching `BASE_URL`).
2. Delegated permissions `openid`, `profile`, `email`. To map groups to roles, add a groups
   claim (Token configuration, Security groups) and `GroupMember.Read.All` (delegated).
3. **Settings, Sign-in**: enable, enter the tenant ID (or a full issuer URL for Authentik or
   another OIDC provider), client ID and secret. Optionally restrict email domains and map
   group IDs to roles.

Sign-in never creates a person: the identity must already exist (synced or created under
People) and hold at least one role. Run directory sync first.

**Geotab:** create a dedicated MyGeotab user with read-only clearance for Devices, Users,
DeviceStatusInfo and StatusData. Note the database name shown on MyGeotab's login screen,
then enter database, user, password and server (usually `my.geotab.com`) under **Settings,
Geotab**, **Test connection**, enable scheduled sync, and **Sync now**. A sync never creates
a vehicle or person by itself; unlinked devices and drivers are listed for an administrator
or supervisor to import or link. Write-back is off by default.

**Document AI (smart upload):** **Settings, Document AI** selects one provider:
OpenAI-compatible (a local Ollama, vLLM, LM Studio or a hosted endpoint), Azure Document
Intelligence, Anthropic, or none (uploads still work, with no suggestion). Keys live in the
database, encrypted. Driver's licences never reach a remote provider whatever you choose.

**Email and Teams:** **Settings, Email** takes the SMTP connection (STARTTLS is required
unless "Allow unencrypted SMTP" is on) and has a test button. **Settings, Alerts** sets the
thresholds (default 30, 14 and 7 days, the expiry day, and weekly while expired),
recipients and channels, including a Microsoft Teams incoming webhook. **Settings, Expiry
digest** schedules the digest. Reminders never contain a document or card number.

---

## Security notes

- **Encrypted at rest by the application:** every credential saved in Settings (directory
  and SSO client secrets, the Geotab password, the SMTP password, Document AI keys, the
  Teams webhook) is encrypted with AES-256-GCM using `GANESHA_SECRET_KEY`; a database dump
  holds ciphertext only. Passwords are bcrypt hashes. This protects a leaked backup, not a
  compromised running process.
- **Not encrypted by the application:** record and card attachments, pending uploads and
  vehicle photos (files under the data volume), and the identifiers in the database (VINs,
  plates, names, emails, and the numbers of any record type set to `keep`). Put the data
  volume and the Postgres volume on **encrypted storage** and encrypt your backups.
- **Back up `GANESHA_SECRET_KEY`** separately from, or alongside, your database backups. If
  it is lost, every stored credential is unrecoverable and must be re-entered.
- **Reverse proxy and TLS:** Ganesha speaks plain HTTP. Terminate TLS in front of it, set
  `BASE_URL` to the exact `https://` address, and set `TRUST_PROXY` so client IPs (rate
  limits, lockout, audit) are real. On Compose behind a proxy on the same host, set
  `GANESHA_BIND=127.0.0.1`. The app sends HSTS, a strict CSP and clickjacking protection on
  https and cannot be framed.
- **Driver's licences are verified, not stored.** With the default `drivers_license` policy
  (`verify_discard`), the photos are checked in memory by the app (no remote provider) and
  dropped. No licence image, number, date of birth, address, barcode text or OCR text is
  written to disk, the database, the logs or the audit log. Only expiry, issue date, state,
  class, endorsements, restrictions and the verification verdict are kept. On every start a
  cleanup removes anything stored before the policy. **Backups taken earlier still hold the
  old copies**; expire them on your normal schedule. No CDL image or number is stored
  either.
- **Outbound connections** to Document AI, the OIDC issuer, SMTP and the Teams webhook are
  checked before use: loopback, link-local and cloud-metadata addresses are always blocked,
  private ranges need `ALLOW_PRIVATE_OUTBOUND=true`, and redirects are not followed.
- **Sign-in:** SSO links by the stable `sub` claim and never auto-links a person who holds a
  local password or the admin role. Per-IP rate limits and a per-account lockout protect
  local login (the lockout never blocks SSO). Sessions end on password change, disable and
  loss of the last role; the last active admin cannot be disabled or demoted. To unlock a
  locked-out local administrator:
  `docker compose exec app node server/dist/index.js unlock <email>`.
- **Uploads:** images over 40 megapixels are refused, EXIF/GPS metadata is stripped from
  stored images, unconfirmed uploads are visible only to the uploader, HR and admin and
  are purged after 7 days.
- **Logs:** 5xx responses are generic, request logs record paths only, and credentials and
  cookies are redacted.

---

## Upgrading

- **Docker Compose:** set `GANESHA_VERSION` in `.env` (or `git pull` for a newer
  `docker-compose.yml`), then `docker compose pull && docker compose up -d`.
- **Kubernetes:** change the image tag in `deploy/k8s/base/deployment.yaml` and re-apply.

Database migrations run automatically on start, under a Postgres advisory lock. **Back up
first** (below). Releases and their notes are listed under **Releases**; the running build
is shown at **Settings, Build**.

## Backup and restore

Ganesha's state is in two places that must be backed up **together**: the Postgres database,
and the data volume (`/data`: attachments, vehicle and profile photos, card images, pending
uploads, branding files). Also keep a copy of `GANESHA_SECRET_KEY`.

```bash
# Docker Compose backup
docker compose exec -T db pg_dump -U ganesha ganesha > ganesha-db.sql
docker compose run --rm --no-deps -T app tar czf - -C /data . > ganesha-data.tgz
```

```bash
# Docker Compose restore (into an empty install of the same or a newer version)
docker compose down
docker compose up -d db
docker compose exec -T db psql -U ganesha -d postgres \
  -c 'DROP DATABASE IF EXISTS ganesha' -c 'CREATE DATABASE ganesha OWNER ganesha'
docker compose exec -T db psql -U ganesha -d ganesha < ganesha-db.sql
docker compose run --rm --no-deps -T app sh -c 'rm -rf /data/* && tar xzf - -C /data' < ganesha-data.tgz
docker compose up -d
```

Restoring a database without its matching data volume (or the reverse) leaves records
pointing at files that do not exist. After a restore, check
`http://127.0.0.1:8080/api/health` and `/api/ready`, then open a record with an attachment
and a vehicle photo. On Kubernetes, back up the Postgres database the way you do for any
other app and snapshot or copy the `ganesha-data` volume.

If a restored or older volume makes every write fail with a permission error, fix the
ownership once: `docker compose run --rm -u root app chown -R node:node /data`
(Kubernetes: see "Upgrading" in [`deploy/k8s/README.md`](deploy/k8s/README.md)).

## Uninstall

- **Docker Compose:** `docker compose down` (add `-v` to also delete the database and data
  volumes, which destroys all data).
- **Kubernetes:** `kubectl delete -k deploy/k8s`. The PersistentVolumeClaim goes with it, so
  snapshot the volume first if you want to keep the data, and drop the database separately.

## Support and contributing

Bug reports and feature requests are welcome as GitHub Issues on this repository. Pull
requests are not accepted, and security issues should be reported privately. See
[CONTRIBUTING.md](CONTRIBUTING.md).
