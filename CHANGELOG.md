# Changelog

Release notes for the published Ganesha images. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [0.1.5] - 2026-10-06

`ghcr.io/root-chain-ventures-llc/ganesha:0.1.5`

### Changed

- **Forms and buttons now use the design kit's interaction components** (pass A of two; the data
  surfaces - skeletons, tables, lightbox, sync progress - come next). Every async button (Sign in,
  every Settings Save / Test / Send test / Sync now / Preview / Import, the record, card, vehicle,
  person and licence sheets, report download, and the confirm dialogs for unlink, end assignment,
  revoke, unassign and delete) shows a spinner while it works, a tick on success and a shake with a
  red outline on failure, never changes width, and keeps its label, variant, size and Enter-to-submit.
  Confirm dialogs stay open while they work and close on success. Fields with a knowable rule (email,
  URL, port, interval, hour, hex colour, VIN, plate, year, expiry after issue, Teams webhook) show
  their verdict inline after the first blur and keep it up to date as you type; typing is never
  blocked and the server's own errors still appear as before. Setup and Add person show a password
  strength meter that agrees with the server's rule (12 characters, at most 72 bytes) and a show/hide
  toggle (Sign in has the toggle too). First-run setup is now a three-step wizard (Organisation,
  Administrator, Done) that makes the same single `POST /api/setup` call, then saves the app and
  organisation names to Branding and offers links into Settings. The SSO allowed domains and group
  lists, the digest recipients and the alert extra recipients are chip fields (paste a list, Enter
  adds, a value typed but not confirmed is kept when you leave the field); what is saved is the same
  array as before. The sign-in page's message is a dismissible, foldable notice, dismissed for the
  browser session only. One motion scale (`--motion-fast` 150 ms, `--motion-base` 220 ms,
  `--motion-slow` 260 ms, `--ease-out`) now drives button press feedback and the kit components, all
  of it off under `prefers-reduced-motion`. Single-line fields are 44 px tall on a phone. No API or
  server change.
- **Data surfaces use the design kit's interaction components** (pass B). Dashboard, Vehicles,
  People, Records, Reports, Audit and the vehicle and person pages show a skeleton shaped like the
  page on first load and hand over to the content without a jump; a search, a filter or a refresh
  keeps what is already on screen. The Dashboard's counts, the bell badge and the Geotab device
  readings roll and flash when a refresh changes them (the Dashboard now refreshes on focus and every
  two minutes), coloured by whether more is good or bad. Sync now (Directory, Geotab) and Smart
  upload show step lists that report only what is really known: the server answers once, so they show
  running, then done with the counts or failed with the reason. The Audit page is a sortable,
  paginated table at desktop width (cards on a phone) with a "N new entries" pill when newer entries
  arrive while you are looking further down. Photos and image attachments open in a lightbox and
  load with a soft focus; vehicle and person photos keep their initials or icon fallback. On a phone
  the list searches are an expanding search field and the list headers stay at the top with their
  main action; the Records views are keyboard-navigable tabs; long notes, licence verification
  detail and audit JSON fold behind "Show more". A field's "required" message now waits for you to
  use that field (or submit), so a form that focuses its first field for you no longer scolds it;
  the sign-in SSO link is 44 px tall on a phone, and the form fields' spacing and padding sit on the
  spacing scale. Every control is now at least 44 px tall on a phone (issue #81): the top-bar menu and
  Smart upload buttons, the drawer's navigation items, switches, checkboxes and radios, chip and tag
  removers, the search clear button, the back links and map links on the detail pages, the Audit
  rows' subject links; desktop sizes are unchanged. No API or server change.

Upgrade: set `GANESHA_VERSION=0.1.5` in `.env` (or pull this repository) and run
`docker compose pull && docker compose up -d`; on Kubernetes change the image tag in
`base/deployment.yaml` and re-apply. No migration.

## [0.1.4] - 2026-10-05

`ghcr.io/root-chain-ventures-llc/ganesha:0.1.4`

### Security

- **Files are now encrypted at rest.** Every file the server stores under `DATA_DIR` - record and
  card attachments and their kept originals, pending Smart-upload files, vehicle photos, synced
  profile photos and branding images - is AES-256-GCM encrypted with a file key derived
  (HKDF-SHA256) from `GANESHA_SECRET_KEY`, bound to the file's path, and written atomically. There
  is no setting to turn it off. Files already on the volume are converted by a background pass on
  the first start after upgrading (one replica at a time, counts-only log line); reads accept both
  forms meanwhile. `rotate-secrets` now also re-encrypts the whole data volume to the new key and
  exits non-zero if any file could not be decrypted. A backup of the data volume is unreadable
  without the key, so keep the key separate from backups. The Postgres data directory is not
  covered: run the database on encrypted storage. Files are decrypted in memory when served (the
  largest upload is 15 MB). The README, `deploy/README.md` and `deploy/k8s/README.md` describe
  backup, restore and rotation. Also corrects `deploy/README.md`, which said sessions have no idle
  timeout: they have a 12 h sliding idle timeout and a 7-day absolute lifetime.

- **Card and document numbers are now encrypted in the database.** The printed number of a card or
  document (fuel and ferry card numbers, policy and registration numbers, transponder ids) and the
  copy of it a Smart upload keeps for review are AES-256-GCM encrypted with a key from
  `GANESHA_SECRET_KEY`, bound to their row; a database dump, backup or volume snapshot no longer
  reveals them. It is always on and needs nothing from the operator. Nothing changes on screen:
  display, supervisor masking, search, Smart-upload matching, reports and CSV behave as before
  (search decrypts and filters in the app; an HMAC blind index keeps exact matches fast).
  The audit log now records only that a number changed and its last few characters, and the
  first start after upgrading scrubs full numbers from older audit entries. Existing rows are
  converted by a background pass (counts-only log line, one replica at a time); `rotate-secrets`
  re-encrypts them to the new key and rebuilds the index. Names, locations, plates, VINs and other
  rows are not encrypted by Ganesha, so use an encrypted volume for the database; losing
  `GANESHA_SECRET_KEY` makes the numbers unrecoverable. Backups taken before upgrading still hold
  the numbers in plaintext.

Upgrade: set `GANESHA_VERSION=0.1.4` in `.env` (or pull this repository) and run
`docker compose pull && docker compose up -d`; on Kubernetes change the image tag in
`base/deployment.yaml` and re-apply. One database migration runs on start, and existing files
and numbers are encrypted in the background. Take a backup first: after this upgrade the data
volume cannot be read by an older version. Keep `GANESHA_SECRET_KEY` safe and separate from
backups.

## [0.1.2] - 2026-10-05

`ghcr.io/root-chain-ventures-llc/ganesha:0.1.2`

### Changed
- **Settings is organised into sections** (My account, Branding, People & sign-in, Fleet & Geotab,
  Documents, Notifications, System) with a left rail on wide screens and a section picker on
  phones. The section is in the URL (`/settings?section=fleet`), so it can be linked and the browser
  back button works. Unsaved edits survive switching sections. Non-admins still see only their own
  account and build info.

Upgrade: set `GANESHA_VERSION=0.1.2` in `.env` (or pull this repository) and run
`docker compose pull && docker compose up -d`; on Kubernetes change the image tag in
`base/deployment.yaml` and re-apply. No migration.

## [0.1.1] - 2026-10-05

`ghcr.io/root-chain-ventures-llc/ganesha:0.1.1`

### Changed
- The word "compliance" is gone from the screens and emails: the default sign-in tagline is now
  "Vehicles & drivers", the report is named "Document status", and the page subtitles and the
  email footer are reworded. API paths and the CSV file name are unchanged. A tagline saved in
  Settings > Branding is not touched.

Upgrade: set `GANESHA_VERSION=0.1.1` in `.env` (or pull this repository) and run
`docker compose pull && docker compose up -d`; on Kubernetes change the image tag in
`base/deployment.yaml` and re-apply. No migration.

## [0.1.0] - 2026-10-05

First public release. `ghcr.io/root-chain-ventures-llc/ganesha:0.1.0`

Ganesha is a vehicle and driver compliance tracker: who drives which vehicle, and whether the
documents, cards and passes that must stay current (insurance, registration, driver's
licences, inspections, fuel and ferry cards, parking passes) are current. It runs as one
container plus Postgres 17, signs people in locally or through Entra ID / Authentik, reads
staff from Microsoft 365, and reads vehicles from Geotab. Maintenance and work orders are out
of scope. Database migrations run automatically on start.

### Added

**Fleet, people and access**
- **Vehicles and driver assignments:** unit number, body type, VIN, plate, status and photo;
  primary and additional drivers with assignment history; VIN decode against NHTSA vPIC
  (supervisor/admin, cached, with a `vehicles.vinLookupEnabled` kill switch for installs with
  no route to the internet). Every signed-in person can list and view every vehicle's basic
  detail; the live location is visible only to the assigned driver, supervisors, HR and admins.
- **People and roles:** the first local admin is created at `/setup`. Roles (`driver`,
  `supervisor`, `hr`, `admin`) are assignments, not a column, so a person can hold several;
  assigning the first role is what makes someone a user. Only an admin grants `hr` or `admin`.
- **Microsoft 365 directory sync** (Graph, client credentials): imports people and photos,
  adopts a pre-created local person by email, resolves managers, and never deletes anyone:
  people who leave the directory are disabled, keeping their history. Guests are skipped
  unless enabled.
- **Entra ID / Authentik sign-in** (OIDC authorization code with PKCE) linked by the stable
  `sub`; group-to-role mapping is supported.
- **HR role and sensitive documents:** `hr` has full read/write on everyone's records and
  cards and no access to system Settings. A record type flagged sensitive is shown in full
  only to its own subject, HR and admin; a supervisor sees status and expiry only and cannot
  create, renew, attach to, delete or override it.
- **Audit:** a filterable, cursor-paged audit log with admin CSV export, per-vehicle and
  per-person history, and "My history" for drivers. Sensitive identifiers are never written
  to it.

**Records, cards and uploads**
- **Record types, records and attachments:** admin-defined types (key, warning window,
  required, required-for-role, sensitive, identifier/issuer labels) with per-subject records,
  renewals that keep history, attachments, and a derived status of `ok`, `expiring`, `expired`
  or `missing` computed the same way everywhere. Records can be deleted (supervisor/admin,
  audited).
- **Cards and passes** (gas, ferry, parking and similar) as assets with a holder, full
  assignment history, a nickname, status (`active`, `lost`, `retired`), editing and image
  replacement. A Records > Documents view lists every vehicle against one document type.
- **Smart upload:** a photo or PDF is read by a configurable Document AI provider (Azure
  Document Intelligence, Anthropic, or an OpenAI-compatible endpoint such as Ollama) and
  suggests where it belongs; a person confirms every suggestion before anything is written.
  HEIC is converted to JPEG, images are auto-rotated and auto-cropped with the original kept
  and restorable, and matching uses VIN, plate and card number.
- **Local-only extraction for licences:** a driver's licence is never sent to any remote
  provider. A local PDF417 (AAMVA) barcode check and an offline OCR read it instead.
- **Branding:** app name, organization, tagline, default theme, primary colour, logo, favicon,
  banner, footer and login message, with contrast computed so text stays readable. Themes:
  Light, Dark, Hacker and Auto.

**Driver's licences: verified, not stored**
- No licence image, licence number, date of birth, address, raw barcode text or OCR text is
  kept. A record-type `retention` policy (`keep` or `verify_discard`) makes `drivers_license`
  verify and discard by default; an admin changes it per type, and switching to verify and
  discard asks for confirmation and deletes stored copies and numbers. A startup cleanup
  removes any pre-existing licence data and marks such records "Not verified, re-verify".
- **Verify licence:** the person, HR or admin photographs the back (barcode) and the front in
  either order. The server decodes the barcode, reads the front, and compares name, licence
  number, expiry and date of birth, and the name against the person record, all locally and
  in memory. Result: `matched`, `partial` (naming which fields disagreed or were unreadable)
  or `failed` (nothing recorded); a back-only check is recorded as barcode only. What is kept:
  expiry, issue date, issuing state, class, endorsements, restrictions and the verification
  verdict. HR and admin can instead record "verified in person".
- **Issuing state:** shown on the licence row ("Verified · WA · Class C · expires <date>") and
  in the Verify licence result. A barcode with no jurisdiction falls back to the front when
  exactly one state or province is named there; otherwise the row says "State not read" and HR
  can set it. Supervisors see state, class, expiry and status, never identifiers,
  endorsements or restrictions. "Verified in person" requires a State/Province (US states, DC,
  Canadian provinces) and takes an optional class. `PUT /api/people/:id/licence-details
  {state, class}` (HR/admin, audited) corrects either one.
- **CDL tagging:** vehicles can require a CDL. A licence whose barcode shows a commercial
  class is recorded as "CDL detected"; HR keeps the paper copy and ticks Hard Copy on File
  (HR/admin only, audited). Until then a driver with a CDL shows "CDL - awaiting HR hard
  copy", and a driver on a CDL vehicle without a verified CDL shows "CDL not verified",
  feeding the rollup, alerts and reports. Assigning an unverified driver to a CDL vehicle
  needs an explicit, audited confirmation. No CDL image or number is stored either.

**Alerts, reports and email**
- **Alerts and reminders:** Settings > Alerts sets thresholds (default 30, 14 and 7 days, the
  expiry day, and weekly while expired), categories, recipients (the holder, their manager or
  all supervisors, HR for people documents, an extra list) and channels (email and Microsoft
  Teams through an incoming webhook). Each alert is sent once per record, expiry date,
  threshold, recipient and channel. A reminder never contains a document or card number.
  Supervisors, HR and admins can send a reminder on demand (once an hour per record per
  channel). A bell in the top bar shows expiring and expired items; missing items are listed
  separately.
- **Reports** (supervisor/HR/admin, JSON preview or CSV): compliance, expiring (30/60/90
  days), assets, vehicles and drivers. The drivers report includes licence state, licence
  class, verification, CDL and CDL verified.
- **Expiry digest email** (SMTP, daily or weekly) grouped by vehicles then drivers, with links
  built from `BASE_URL`, preview and send-now. Per-driver reminders are alerts on their own
  daily run, not part of the digest; a digest with no recipients is an error.

**Geotab (read-only by default)**
- A connector matches devices to vehicles by VIN, serial and plate and records odometer,
  engine hours and the current driver. A sync never creates vehicles or people on its own;
  admins and supervisors can import unlinked devices as vehicles (optional VIN decode), link a
  Geotab driver to an existing person, or create one person from a driver as a deliberate
  fallback. Linking a Geotab driver that another person holds, or to a person who already
  holds a different one, is refused with 409 unless forced (audited).
- A live device card on the vehicle page (status, location, driving or parked, odometer,
  engine hours, current driver, last log record) with a 60 second cache; it falls back to the
  last sync when Geotab is unreachable.
- VIN, plate, plate state and serial track a Geotab value and a manual value separately; a
  manual edit always wins and can be reset to the Geotab value.
- Optional write-back, off by default, behind a master switch and per-field flags (name,
  plate, VIN, comment, groups, driver change, archive on retire), with a permission check,
  confirm prompts and a dry run. No odometer or engine-hours write-back.
- An optional setting gives the current Geotab driver an additional assignment on the vehicle.

**Deployment and operations**
- One image and one `docker-compose.yml` (app on `:8080`, Postgres 17 on loopback), an
  `install.sh` that writes `.env`, generates the secrets and starts the stack, Kubernetes
  manifests as a Kustomize base plus a 3-replica HA overlay, a health check
  (`/api/health`, `/api/ready`) and a build stamp at Settings > Build and `/api/version`.
- The server ships as one minified bundle and the client build has no source maps.
- Passwords are hashed with bcrypt cost 12 and must be at least 12 characters wherever one is
  set.
- Licensed under the RCV Community License 1.1.

### Security

Behaviour operators must know about is marked **Action**.

- **Secrets at rest:** every credential Settings stores (directory and SSO client secrets, the
  Geotab password, the SMTP password, Document AI keys, the Teams webhook) is encrypted with
  AES-256-GCM, bound to its settings field, with key rotation
  (`node server/dist/index.js rotate-secrets`). **Action:** set `GANESHA_SECRET_KEY` (or
  `GANESHA_SECRET_KEY_FILE`); the image refuses to start without one, and
  `GANESHA_SECRET_KEY_PREVIOUS` supports rotation. Back the key up.
- **SSO:** sign-in links by `sub`; a person bound to a different `sub` is refused; email
  linking needs a verified email and never auto-links a row with a local password or the admin
  role (an admin links explicitly). ID tokens are verified for issuer, expiry and subject;
  multi-tenant endpoints need `allowedDomains`.
- **Licences never reach a remote AI:** every upload is screened locally first, and a licence
  or an unscreenable upload is read locally only.
- **Uploads:** pending uploads are visible to the uploader, HR and admin; files and
  suggestions are deleted on accept, reject and record delete; unconfirmed uploads are purged
  after 7 days. Images over 40 MP are refused, PDFs render at most 10 pages, and uploads are
  rate limited (`UPLOAD_RATE_PER_HOUR`).
- **Outbound requests:** loopback, link-local and cloud-metadata addresses are always blocked
  for Document AI, OIDC, SMTP and the Teams webhook; private ranges need
  `ALLOW_PRIVATE_OUTBOUND=true`. **Action:** an on-premises model or LAN mail relay needs that
  flag.
- **Action: SMTP requires STARTTLS** unless "Allow unencrypted SMTP" is on.
- **Action: the image refuses a non-https `BASE_URL`** unless `ALLOW_INSECURE_HTTP=true`. CSRF
  checks `Origin` against `BASE_URL`, so it must be exactly what users type. HSTS, Secure
  cookies, a strict CSP and clickjacking headers apply on https.
- **Sessions:** a person's sessions end on password change, disable, loss of the last role and
  SSO unlink; 12 hour idle and 7 day absolute limits and a per-person cap are configurable.
  The last active admin cannot be disabled or demoted.
- **Sign-in:** per-IP rate limits and per-email lockout (local lockout never blocks SSO),
  first-admin setup is serialised with an optional `SETUP_TOKEN`, and `TRUST_PROXY` accepts a
  hop count or CIDR list. Break-glass: `node server/dist/index.js unlock <email>`.
- **Errors and logs:** 5xx responses are generic, request logs record paths only, and
  credentials and cookies are redacted.
- **Vehicles:** list and detail omit Geotab identifiers, notes, odometer and driver details
  for people without access; out-of-scope reads return 404.
- **Container:** read-only root, all capabilities dropped, `no-new-privileges`, memory and pid
  limits.
- **Not in this release:** attachment encryption at rest. Attachments, vehicle photos and
  database contents other than Settings credentials are not encrypted by the application; use
  encrypted volumes and encrypted backups.
