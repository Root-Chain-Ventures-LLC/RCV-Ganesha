# Ganesha on Kubernetes

Plain manifests: `kubectl apply -k .` or `kustomize build .`. No Helm, nothing to install
first. Paths below are relative to this directory (`deploy/k8s/`).

## Two shapes: single (default) and HA on 3 nodes

This directory is a Kustomize **base** plus one **overlay**:

- **`base/`**: one replica, a `ReadWriteOnce` volume, `strategy: Recreate`.
  `kubectl apply -k deploy/k8s` (from the repository root) or `kubectl apply -k .` (from
  here) deploys it; the top-level `kustomization.yaml` is a one-line pointer at `base/`.
- **`overlays/ha/`**: the 3-node choice, `kubectl apply -k overlays/ha`. Same app, same
  Secret, same Service, Ingress and ConfigMap from `base/`, patched for 3 replicas instead
  of 1.

Pick one, not both, against a given namespace: `overlays/ha` builds `base/` in, it does not
sit alongside it.

### What `base/` deploys

One replica behind a `ReadWriteOnce` volume, a ClusterIP Service, and an Ingress that
terminates TLS and talks plain HTTP to the pod. Ganesha never terminates TLS itself: there
is no certificate inside the container and no redirect from HTTP to HTTPS in the app, so
your ingress controller (or gateway) must be the one doing TLS.

**Do not raise `replicas` on `base/` directly; use `overlays/ha` instead.** `DATA_DIR`
(synced Microsoft 365 profile photos, uploaded vehicle photos, record and card attachments,
pending smart-upload files) is plain files on one volume with one writer. Schema migrations
are not the blocker, because they run on every start under a Postgres advisory lock and two
instances racing to migrate is safe by design. Two pods mounting the same `ReadWriteOnce`
volume, or both writing into what should be one attachments tree, is not safe.
`base/deployment.yaml`'s `strategy: Recreate` is what keeps an upgrade from briefly running
two pods against the current volume.

### What `overlays/ha` adds on top of `base/`

Everything in `base/`, patched for 3 replicas spread across 3 nodes:

| What | How | Why |
|---|---|---|
| `replicas: 3` | `overlays/ha/deployment-ha.yaml` | The 3-node shape. |
| Shared Postgres | nothing extra | There is no per-replica database state, so one Postgres serves any number of replicas. |
| `ReadWriteMany` volume | `overlays/ha/pvc-rwx.yaml` patches `accessModes` | 3 pods now read and write the same `DATA_DIR` tree at once. Needs a storage class that actually provides RWX: NFS, CephFS or Longhorn with `shareManager` volumes. A plain cloud block-storage class (EBS, most default local-path provisioners) does **not**; check `kubectl get storageclass` before applying. Object storage is not implemented. |
| `strategy: RollingUpdate`, `maxUnavailable: 0`, `maxSurge: 1` | `overlays/ha/deployment-ha.yaml` | Safe now that the volume supports concurrent writers; the rollout never drops below 3 ready pods. |
| `topologySpreadConstraints` on `kubernetes.io/hostname`, `whenUnsatisfiable: DoNotSchedule` | `overlays/ha/deployment-ha.yaml` | Keeps the 3 pods off the same node, so one node failing costs at most one pod. A commented `ScheduleAnyway` alternative is in the same file for clusters with fewer than 3 worker nodes, where `DoNotSchedule` would leave pods permanently `Pending`. |
| `PodDisruptionBudget`, `minAvailable: 2` | `overlays/ha/pdb.yaml` | Bounds *voluntary* disruption (node drain, cluster-autoscaler scale-down) to one pod at a time. Does not protect against a node dying outright; the topology spread above does that. |
| `TRUST_PROXY: "1"` | `overlays/ha/configmap-trustproxy.yaml` | `base/` already ships this hop count, so the patch is a no-op value change kept explicit on purpose: at 3 replicas behind a load balancer or ingress, every pod must trust `X-Forwarded-*` from that ingress specifically. Do not put another internal proxy between it and the Service that could inject its own forwarded headers first. Use `2` if a cloud load balancer sits in front of the ingress controller, or a comma-separated CIDR list of the ingress and load-balancer addresses; `true` (trust every hop) also works but lets a client spoof its IP. |
| Readiness and liveness probes | unchanged, inherited from `base/` | `/api/health` and `/api/ready` behave identically per pod. |

**Sticky sessions are not required** in front of `overlays/ha`. Sessions are opaque random
tokens validated against the `sessions` table on every request, so any pod can serve any
request for any signed-in person: the session lives in shared Postgres, not in pod memory.
The same is true of CSRF protection (a stateless same-origin check) and OIDC sign-in's
state, nonce and PKCE verifier, which ride in a short-lived cookie on the caller's browser
and never in server memory. A sign-in that starts on one pod can finish its callback on a
different one.

**Background jobs run on one replica at a time, by design.** The scheduled loops (directory
sync, the Geotab connector sync, and the expiry digest) each tick on every pod,
but every tick starts by taking a `pg_try_advisory_lock` in Postgres; a pod that does not
get the lock skips that tick and checks again next time. With 3 replicas only one of them
ever runs a given sync or send. No coordination beyond Postgres is needed.

**Upgrade behaviour** differs from `base/`: `overlays/ha` uses `RollingUpdate` with
`maxUnavailable: 0`, so an upgrade adds one new pod (`maxSurge: 1`), waits for it to pass
`startupProbe` and `readinessProbe`, then removes one old pod, repeating until all 3 are the
new version. That is zero-downtime from the Service's point of view, at the cost of briefly
running two image versions at once against the same Postgres and `DATA_DIR` (safe:
migrations are additive and advisory-lock-serialised). `base/`'s `Recreate` strategy always
has a few seconds with zero pods up.

**Drain and eviction.** With the PDB in place, `kubectl drain` on any one node succeeds (it
can evict the one pod `minAvailable` allows), but a drain that would take a second Ganesha
pod down at the same time blocks until the cluster has 3 healthy pods again. That is
expected behaviour, not a stuck drain.

## Postgres

**Ganesha does not bundle a database on Kubernetes.** Postgres (14 or newer; the Docker
Compose install runs 17) is Ganesha's only storage backend, and here it is a server you
already run. Use **one database and one role per app**, never a schema shared between
apps. `create-db.sql` in this directory creates Ganesha's; run it once, as a superuser,
against that server:

```bash
psql "$POSTGRES_ADMIN_URL" -v db_password='<a strong, generated password>' \
  -f create-db.sql
```

Then put the resulting URL in the Secret (see below). No extensions are required. This is
identical for `base/` and `overlays/ha`: the database is multi-writer-safe; only `DATA_DIR`
needs the overlay's RWX patch.

## Before you apply

Edit these in `base/` (`overlays/ha` inherits them):

| Where | What |
|---|---|
| `base/configmap.yaml` | `BASE_URL`: the public `https://` URL. It controls the session cookie's `Secure` flag, HSTS and the CSP's `upgrade-insecure-requests` directive, and the same-origin check on writes; it does **not** make the app itself speak TLS. It must be exactly what people type in the browser. |
| `base/ingress.yaml` | the host (twice: `spec.tls[0].hosts` and `spec.rules[0].host`), `ingressClassName`, and how the certificate is issued |
| `base/pvc.yaml` | `storage`, and `storageClassName` if the cluster has no usable default (`overlays/ha` additionally needs that class to support `ReadWriteMany`) |
| `base/deployment.yaml` | the image tag, pinned to `0.1.6` here; change it to upgrade |

Then create the Secret out of band. `base/secret.example.yaml` is a template with no values
in it and is deliberately **not** in any `kustomization.yaml`, so no credential can reach a
repository through it:

```bash
kubectl create namespace ganesha
kubectl -n ganesha create secret generic ganesha \
  --from-literal=DATABASE_URL="postgres://ganesha:<password>@<postgres-host>:5432/ganesha" \
  --from-literal=GANESHA_SECRET_KEY="$(openssl rand -base64 32)"
kubectl apply -k .                      # base/, 1 replica
# or
kubectl apply -k overlays/ha            # HA, 3 replicas
```

`DATABASE_URL` and `GANESHA_SECRET_KEY` are the two required secrets, for both shapes.
There is no `SESSION_SECRET` to set: sessions are opaque random tokens the server stores
(hashed) in its own `sessions` table and validates on every request, so nothing needs to
survive a restart or be shared between replicas other than the database itself. The first
administrator is created from the running app's setup screen (`/setup`, open only while no
person exists yet), not from an environment variable. To require a token there, add
`SETUP_TOKEN` to the Secret.

`GANESHA_SECRET_KEY` (32 bytes, base64 or 64 hex characters) is the master key every
credential saved in Settings is encrypted with before it reaches Postgres. The app refuses
to start without it. Every pod reads the same value from the one `ganesha` Secret via
`envFrom`, so replicas never disagree about it. **Back this key up**, separately from or
alongside your usual Kubernetes Secret backup: lose it and every already-stored credential
(directory and SSO client secrets, the Geotab password, the SMTP password, Document AI API
keys, the Teams webhook) becomes unrecoverable ciphertext, with no recovery path other than
re-entering each one. To rotate it, set `GANESHA_SECRET_KEY_PREVIOUS` to the old value
alongside the new `GANESHA_SECRET_KEY`, roll the deployment, then run
`kubectl -n ganesha exec deploy/ganesha -- node server/dist/index.js rotate-secrets` and
drop `GANESHA_SECRET_KEY_PREVIOUS` afterwards.

Everything else (Microsoft 365 directory sync and SSO client secrets, the Geotab service
account, Document AI provider keys, the SMTP password) is configured in the Ganesha UI
(Settings, admin-only) and stored encrypted in the database, not here. That protects a
database backup or leak, not a compromised, already-running pod, which holds the key in
memory and can call the same Settings API an administrator can. Protect the Postgres
database and this Secret the way you would protect any other secret store.

Other settings from the main configuration table in the repository README (for example
`ALLOW_PRIVATE_OUTBOUND`, `UPLOAD_RATE_PER_HOUR`, `SESSION_IDLE_TIMEOUT_HOURS`) can be
added to `base/configmap.yaml` (or to the Secret when sensitive).

**Login rate limiting is per pod, not cluster-wide.** `/api/auth/login`, `/api/setup` and
the OIDC start and callback routes are rate-limited in memory, which is fine for the
single-replica `base/` shape. On `overlays/ha` an attacker spread across all 3 pods (a
Service balances round-robin-ish, not stickily) effectively gets 3x the per-IP limit before
the database-backed per-email lockout, which is shared through Postgres regardless of
replica count, catches them.

## Health probes

`livenessProbe` and `startupProbe` hit `/api/health`, which never touches the database: a
database outage alone should not get the pod killed, since a restart cannot fix that.
`readinessProbe` hits `/api/ready`, which does, and returns `503` when Postgres is
unreachable, taking the pod out of the Service's rotation until it recovers.
`startupProbe` is generous on purpose: the first start runs every migration against an
empty database, under the advisory lock mentioned above, and the HTTP listener does not
open until that finishes. The probes are identical per pod in both shapes.

## Pulling the image

The image is public and needs no login:

```bash
docker pull ghcr.io/root-chain-ventures-llc/ganesha:0.1.6
```

If you mirror it into a registry of your own that does need credentials, create the secret
in this namespace and add `imagePullSecrets` to the pod spec yourself:

```bash
kubectl -n ganesha create secret docker-registry <name> \
  --docker-server=<your registry> --docker-username=<user> --docker-password=<token>
```

## Upgrading

**`base/`.** Bump the image tag and re-apply. `Recreate` stops the old pod before the new
one starts, so expect a few seconds of downtime; migrations run on start. Take a Postgres
backup (`pg_dump`) and a volume snapshot (or a copy of `/data`) before upgrading.

**`overlays/ha`.** Bump the image tag and re-apply. `RollingUpdate` (`maxUnavailable: 0`,
`maxSurge: 1`) rolls one pod at a time with no gap in Service coverage (see "Upgrade
behaviour" above). The same backup advice applies; the PDB does not exempt an upgrade from
needing one.

**A volume whose files are owned by the wrong user.** A volume restored from a backup taken
as root, or hand-created without `fsGroup`, can come up with `/data` owned by the wrong
user, which then fails every write with `EACCES`. Fix it once with a throwaway pod running
as root against the same PVC:

```bash
kubectl -n ganesha run ganesha-chown --rm -it --restart=Never \
  --image=ghcr.io/root-chain-ventures-llc/ganesha:0.1.6 \
  --overrides='{"spec":{"securityContext":{"runAsUser":0},"containers":[{"name":"ganesha-chown","image":"ghcr.io/root-chain-ventures-llc/ganesha:0.1.6","command":["chown","-R","1000:1000","/data"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"ganesha-data"}}]}}'
```

## Checking the manifests without a cluster

`kustomize build base` and `kustomize build overlays/ha` render each shape; pipe the output
to a schema checker such as `kubeconform -strict` to validate it against the Kubernetes
JSON schemas without applying anything.

## Troubleshooting

**Pod crashlooping on a write.** `readOnlyRootFilesystem: true` is set, with an `emptyDir`
at `/tmp`. Everything the app writes should land in `/data` or `/tmp`; the logs name the
path.

**`/api/ready` returns 503.** Postgres is unreachable: check `DATABASE_URL` in the Secret
and that the Postgres server and the `ganesha` database and role (see `create-db.sql`) are
up. `/api/health` still answers `200` in this state: the process itself is fine, only its
dependency is down.

**`overlays/ha` pods stuck `Pending`.** Either the storage class does not provide
`ReadWriteMany` (check `kubectl get storageclass` and the provisioner's documentation) or
the cluster has fewer than 3 nodes and `topologySpreadConstraints`'
`whenUnsatisfiable: DoNotSchedule` has nowhere left to place the third pod. Swap to the
commented `ScheduleAnyway` block in `overlays/ha/deployment-ha.yaml`.

**Which build is running.** Settings, then Build (any signed-in account), or
`GET /api/version` with a session. A release image reports its version, commit and build
time.
