#!/usr/bin/env bash
# Ganesha installer: writes .env (generating the secret key and database password),
# pulls the published image, starts the stack, waits for health and prints the URL.
# Safe to re-run: an existing .env is kept and only empty secrets are filled in.
set -euo pipefail

cd "$(dirname "$0")"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx \033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker not found. Install Docker Engine first."
docker compose version >/dev/null 2>&1 || die "docker compose v2 not found. Install the Compose plugin."

# docker-compose.yml uses the optional env_file form, which needs Compose 2.24 or newer.
compose_version="$(docker compose version --short 2>/dev/null || true)"
compose_version="${compose_version#v}"
cv_major="${compose_version%%.*}"
cv_rest="${compose_version#*.}"
cv_minor="${cv_rest%%.*}"
case "${cv_major}${cv_minor}" in
  ''|*[!0-9]*) warn "Could not read the Docker Compose version ('${compose_version}'); continuing." ;;
  *)
    if [ "$cv_major" -lt 2 ] || { [ "$cv_major" -eq 2 ] && [ "$cv_minor" -lt 24 ]; }; then
      die "Docker Compose ${compose_version} is too old; 2.24 or newer is required."
    fi
    ;;
esac

# Random hex without assuming openssl is present (openssl is preferred).
rand_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1"
  else
    head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# Value of KEY in .env: the last assignment, surrounding quotes and spaces removed.
env_get() {
  local line
  line="$(grep -E "^[[:space:]]*$1=" .env | tail -n 1 || true)"
  line="${line#*=}"
  line="${line%%#*}"
  line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
  printf '%s' "$line"
}

# Set KEY=VALUE in .env, replacing an existing line or appending one. VALUE must not contain
# '|', '&' or a backslash (the generated values are plain hex).
env_set() {
  if grep -qE "^$1=" .env; then
    # Portable in-place edit: BSD sed (macOS) needs an argument to -i, GNU sed does not.
    if sed --version >/dev/null 2>&1; then
      sed -i "s|^$1=.*|$1=$2|" .env
    else
      sed -i '' "s|^$1=.*|$1=$2|" .env
    fi
  else
    printf '%s=%s\n' "$1" "$2" >> .env
  fi
}

if [ -f .env ]; then
  say "Using the existing .env (delete it to start over)."
else
  [ -f .env.example ] || die ".env.example is missing; run this from a clone of the release repository."
  say "Writing .env from .env.example"
  cp .env.example .env
fi
chmod 600 .env

generated_key=0
if [ -z "$(env_get GANESHA_SECRET_KEY)" ] && [ -z "$(env_get GANESHA_SECRET_KEY_FILE)" ]; then
  env_set GANESHA_SECRET_KEY "$(rand_hex 32)"
  generated_key=1
  say "Generated GANESHA_SECRET_KEY in .env"
fi
if [ -z "$(env_get GANESHA_DB_PASSWORD)" ]; then
  env_set GANESHA_DB_PASSWORD "$(rand_hex 24)"
  say "Generated GANESHA_DB_PASSWORD in .env"
fi

BASE_URL="$(env_get BASE_URL)"
GANESHA_PORT="$(env_get GANESHA_PORT)"
GANESHA_PORT="${GANESHA_PORT:-8080}"
ALLOW_INSECURE_HTTP="$(env_get ALLOW_INSECURE_HTTP)"
GANESHA_VERSION="$(env_get GANESHA_VERSION)"
SETUP_TOKEN="$(env_get SETUP_TOKEN)"

[ -n "$BASE_URL" ] || die "BASE_URL is not set in .env"

case "$BASE_URL" in
  https://*) ;;
  *)
    if [ "$ALLOW_INSECURE_HTTP" != "true" ]; then
      die "BASE_URL must start with https:// (the server refuses to start otherwise). Edit .env, or set ALLOW_INSECURE_HTTP=true for a local trial, then re-run."
    fi
    warn "BASE_URL is not https:// and ALLOW_INSECURE_HTTP=true: acceptable for a local trial only."
    ;;
esac

if [ "$BASE_URL" = "https://ganesha.example.com" ]; then
  warn "BASE_URL is still the example value. Sign-in links, email links and SSO redirects will point at ganesha.example.com."
  warn "Edit .env and re-run ./install.sh once you know the real hostname."
fi

say "Pulling ghcr.io/root-chain-ventures-llc/ganesha:${GANESHA_VERSION:-0.1.0}"
docker compose pull

say "Starting"
docker compose up -d

say "Waiting for health"
# /api/health is answered over plain HTTP on the published port, so this probe needs no
# certificate handling even though the public URL is HTTPS.
healthy=0
for i in $(seq 1 60); do
  if curl -fsS --max-time 3 "http://127.0.0.1:${GANESHA_PORT}/api/health" >/dev/null 2>&1; then
    say "Healthy after ${i} attempt(s)."
    healthy=1
    break
  fi
  sleep 2
done
if [ "$healthy" != 1 ]; then
  warn "Never came up. Recent logs:"
  docker compose logs --tail 40 app >&2 || true
  die "Health check failed at http://127.0.0.1:${GANESHA_PORT}/api/health"
fi

echo
say "Ganesha is running at ${BASE_URL}"
say "On this host (plain HTTP, for a quick check): http://127.0.0.1:${GANESHA_PORT}"
echo
say "First run: open ${BASE_URL%/}/setup and create the first administrator account."
if [ -n "$SETUP_TOKEN" ]; then
  say "SETUP_TOKEN is set in .env: enter its value in the extra field on that page."
else
  warn "If this host can be reached before you finish setup, set SETUP_TOKEN in .env, then run 'docker compose up -d' again."
fi

if [ "$generated_key" = 1 ]; then
  echo
  warn "A new GANESHA_SECRET_KEY was written to .env. Back it up somewhere safe, separately from"
  warn "the database backups: without it every credential saved in Settings is unrecoverable."
fi
echo
say "Ganesha speaks plain HTTP. Put a reverse proxy that terminates TLS in front of it, and set"
say "TRUST_PROXY in .env (and GANESHA_BIND=127.0.0.1 if the proxy runs on this host)."
