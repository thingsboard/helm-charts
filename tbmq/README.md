# Helm Chart for TBMQ Cluster

TBMQ is a high-performance MQTT message broker capable of handling 4M+ concurrent client connections,
delivering 3M+ messages per second per single cluster node with low latency. In cluster mode,
TBMQ scales to 100M+ concurrently connected clients.

This chart deploys a TBMQ cluster on Kubernetes. The same chart supports both editions of TBMQ:

- **Community Edition (CE)** — open-source, default images.
- **Professional Edition (PE)** — commercial edition with additional features. Activated by passing the
  bundled `values-pe.yaml` overlay, which switches the broker and integration-executor images to the
  PE variants. All templates, configuration keys, and operational behavior are identical between editions.

**Documentation & Resources:**

- TBMQ [Documentation](https://thingsboard.io/products/mqtt-broker/)
- TBMQ GitHub [Repository](https://github.com/thingsboard/tbmq)
- ThingsBoard Charts GitHub [Repository](https://github.com/thingsboard/helm-charts)

> **Trademarks:** This software listing is packaged by the TBMQ Team. The respective trademarks
> mentioned in the offering are owned by the respective companies, and use of them does not imply
> any affiliation or endorsement.

## Architecture

The chart deploys only TBMQ application components:

- `tbmq-node` — broker StatefulSet (default 2 replicas). Exposes MQTT (1883), MQTTS (8883), MQTT-WS
  (8084), MQTT-WSS (8085), and an HTTP management API (8083).
- `tbmq-ie` — Integration Executor StatefulSet (default 2 replicas). Exposes HTTP (8082).
- Helm hooks for one-shot install Pod and upgrade Job that run TBMQ's database schema initializer
  or migration tool.
- Optional `Ingress` and `Service` resources for HTTP and MQTT load balancing
  (`nginx`, `aws`, `azure`, or `gcp` flavors).

Infrastructure dependencies — PostgreSQL, Kafka, and a Redis-compatible cache — must be deployed
separately. Use whatever fits your environment: operators (CrunchyData PGO, Strimzi, Valkey
Operator), managed services (RDS, MSK, ElastiCache), or raw manifests. The chart connects to your
existing instances via the values you provide.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- Persistent Volume provisioner (only needed if your infrastructure components use PVs)
- An external PostgreSQL instance (with an empty database created for TBMQ)
- An external Kafka cluster
- An external Redis-compatible cache (Redis, Valkey, Dragonfly, etc.) — standalone or cluster

For a working step-by-step example using Minikube with CrunchyData PGO, Strimzi Kafka, and Valkey,
see the [Minikube Deployment Guide](docs/minikube/README.md).

## Installing

### Step 1: Add the TBMQ Helm Repository

```bash
helm repo add tbmq-helm-chart https://helm.thingsboard.io/tbmq
helm repo update
```

### Step 2: Prepare Your `values.yaml`

Export the chart defaults as a starting point, then edit it to match your environment:

```bash
helm show values tbmq-helm-chart/tbmq-cluster > values.yaml
```

At a minimum you need to set:

- `postgresql.host` and credentials (or `existingSecret`)
- `kafka.bootstrapServers`
- `redis.nodes` (cluster mode is the default) — or `redis.connectionType: standalone` plus `redis.host`/`redis.port` — and credentials if `usePassword: true`

See [Infrastructure Configuration](#infrastructure-configuration) for full parameter reference.

> **Important:** Do not set `installation.installDbSchema: true` in `values.yaml`. Pass it via
> `--set` on the `helm install` command instead. Persisting it in your values file means the install
> pod will also run on every subsequent `helm upgrade` (because the post-install hook is also bound
> to `post-upgrade` to allow recovery from a forgotten flag).

### Step 3: Install

#### Community Edition (CE)

```bash
helm install my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f values.yaml \
  --set installation.installDbSchema=true
```

#### Professional Edition (PE)

PE deploys exactly the same chart as CE — only the broker and integration-executor images differ
(`thingsboard/tbmq-pe-node` and `thingsboard/tbmq-pe-integration-executor`), and **PE additionally
requires a license**.

##### 1. Provide your license

You can either let the chart create a Secret from a value you supply, or point the chart at a
Secret you've already created.

**Recommended (production):** pre-create a Kubernetes Secret with your license, then reference
it from values:

```bash
kubectl create secret generic my-tbmq-license -n <namespace> \
  --from-literal=license-key=YOUR_LICENSE_VALUE
```

```yaml
license:
  existingSecret: my-tbmq-license
  # existingSecretLicenseKey defaults to "license-key" — match what you used above
```

**Quick (test / dev):** paste the license value into your values file and the chart will create
the Secret for you (`<release>-tbmq-license-secret`):

```yaml
license:
  secret: YOUR_LICENSE_VALUE
```

You can also pass the license value via `--set license.secret=…` on the install command — but
remember it lands in the helm release manifest stored inside the cluster.

Only the broker StatefulSet validates the license, so the chart injects two env vars there.
The IE StatefulSet, the install Pod, and the pre-upgrade Job all run code paths that do **not**
check the license, so they do **not** receive these env vars and do **not** depend on the Secret.

- `TBMQ_LICENSE_SECRET` — read from the Secret above.
- `TBMQ_LICENSE_INSTANCE_DATA_FILE` — path to a per-pod license cache file. The default
  (`/data/tbmq-instance-license-$(TB_SERVICE_ID).data`) lives on the broker's `/data` directory,
  which is backed by a per-pod PVC when `tbmq.persistence.enabled=true` (the default — see
  [Persistence](#persistence) below). `$(TB_SERVICE_ID)` is set to the pod name (via the
  downward API), so each replica gets its own file path — and, more importantly, presents its
  own stable cluster id to the license server (one license slot per cluster id). **Keep
  persistence enabled for PE:** if `/data` is an `emptyDir` and a Pod is recreated, the cache
  file is wiped and the broker re-registers as a fresh instance with a new cluster id —
  burning a license slot and (for single-bind licenses) hitting `CLUSTER_ID_MISMATCH(114)` on
  the next start. Override `license.instanceDataFile` only if you mount a different writable
  path.

##### 2. Select the PE images

Two equivalent ways:

**Option A — apply the bundled `values-pe.yaml` overlay (recommended):**

```bash
helm pull tbmq-helm-chart/tbmq-cluster --untar --untardir /tmp

helm install my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f /tmp/tbmq-cluster/values-pe.yaml \
  -f values.yaml \
  --set installation.installDbSchema=true
```

When installing from a local chart directory, the overlay is right there:

```bash
helm install my-tbmq ./tbmq \
  -f tbmq/values-pe.yaml \
  -f values.yaml \
  --set installation.installDbSchema=true
```

**Option B — inline overrides:**

```bash
helm install my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f values.yaml \
  --set tbmq.image.repository=thingsboard/tbmq-pe-node \
  --set tbmq.image.tag=<appVersion>PE \
  --set tbmq-ie.image.repository=thingsboard/tbmq-pe-integration-executor \
  --set tbmq-ie.image.tag=<appVersion>PE \
  --set installation.installDbSchema=true
```

Either form must be repeated on every subsequent `helm upgrade` for this release — Helm does not
remember overlays or `--set` flags between invocations.

> **Note on tags:** `values-pe.yaml` pins `<appVersion>PE` (e.g., `2.3.0PE`) — that's the convention
> the PE images use on Docker Hub. The CE/PE image tags are not interchangeable.

> **Tip:** `my-tbmq` is the **Helm release name**. Pick any name. It is used as the prefix for all
> deployed resources and as the reference for future `helm` commands against this release.

### Step 4: Verify the Install

```bash
# List the broker, integration executor, and install-pod resources
kubectl get pods -n <namespace> -l 'app in (my-tbmq-tbmq-node,my-tbmq-tbmq-ie,install-job)'
```

(The chart sets only the bare `app:` label — there is no `app.kubernetes.io/instance` selector to filter by release name.)

The install pod (`my-tbmq-install-pod`) runs to completion (its `restartPolicy` is `OnFailure`,
so a failed container restarts in-pod until it succeeds or the hook timeout fires), creates the
schema, then exits. The hook policy is `hook-succeeded,before-hook-creation`: Helm deletes the
pod **only when it succeeds**; on failure the pod is **left in place** so you can inspect logs,
and it is auto-cleaned the next time the hook runs (e.g., the next `helm upgrade`). The install
hook has a 300s timeout. The `my-tbmq-tbmq-node-*` and `my-tbmq-tbmq-ie-*` StatefulSet pods
should reach `Running` and pass readiness probes within a minute or two after the install pod
succeeds.

```bash
# While the pod runs:
kubectl logs my-tbmq-install-pod -n <namespace> -f

# If it has already finished and was restarted (restartPolicy: OnFailure):
kubectl logs my-tbmq-install-pod -n <namespace> --previous
```

If a successful install pod was deleted before you could grab logs, re-run with `helm install --debug`
so Helm streams hook output to your terminal.

## Updating Configuration

Routine configuration changes — scaling replicas, adjusting resource limits, modifying load balancer
annotations, etc. — are applied via `helm upgrade` against the same release:

```bash
helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster -f values.yaml
```

For PE deployments, keep the overlay in the command:

```bash
helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f /tmp/tbmq-cluster/values-pe.yaml \
  -f values.yaml
```

### Pod Restart Behavior

When `enableChecksumAnnotations: true` (the default), `helm upgrade` rolls Pods whenever any of
their inputs change. The triggers differ between the broker and the IE because the IE does not
connect to PostgreSQL or Redis and does not validate the PE license.

**Broker (`tbmq-node`):**

- Default Java options ConfigMap (`conf` key)
- `tbmq.customEnv` ConfigMap
- PostgreSQL connection ConfigMap and password Secret
- Redis connection ConfigMap and password Secret
- Kafka connection ConfigMap
- License Secret (PE only — checksummed only when `license.secret` or `license.existingSecret` is set)

**Integration Executor (`tbmq-ie`):**

- Default Java options ConfigMap (`conf` key)
- `tbmq-ie.customEnv` ConfigMap
- Kafka connection ConfigMap

Logback ConfigMap changes do **not** trigger restart on either StatefulSet. Both broker and IE
logback configs declare `<configuration scan="true" scanPeriod="10 seconds">` and pick up logback
changes within ~10 seconds of the ConfigMap propagating to the Pod. `tbmq.enableChecksumAnnotations`
and `tbmq-ie.enableChecksumAnnotations` are independent — set either to `false` to opt that
StatefulSet out of automatic rolling on input changes.

## Upgrading

A TBMQ chart upgrade may include a database schema migration when the `appVersion` changes. Always
back up your PostgreSQL database before upgrading.

### Backup (Recommended)

Follow the procedure documented by your PostgreSQL provider (operator, cloud-managed service, or
self-managed instance) to create a logical or physical backup before proceeding.

### Standard Upgrade Procedure

The same steps apply to **CE → newer CE** and **PE → newer PE** upgrades. Only the values overlay
differs.

1. **Scale `tbmq-node` (and optionally `tbmq-ie`) to 0 replicas** so no application is reading or
   writing while the schema migration runs:

   ```bash
   kubectl scale statefulset/my-tbmq-tbmq-node --replicas=0 -n <namespace>
   # Recommended on TBMQ version bumps (broker ↔ IE protocol coupling):
   kubectl scale statefulset/my-tbmq-tbmq-ie   --replicas=0 -n <namespace>
   ```

   The IE doesn't connect to PostgreSQL itself, so the schema migration doesn't directly affect
   it. Scaling it down is still recommended on TBMQ version bumps, because the IE communicates
   with the broker over Kafka and the message contract / API surface can change between releases
   — leaving the IE running against a freshly upgraded broker (or a broker that's been scaled to
   zero) can produce noisy errors. For routine config-only `helm upgrade`s on the same TBMQ
   version you can leave the IE running.

2. **Run the upgrade.** The `upgrade.upgradeDbSchema=true` flag triggers the pre-upgrade Helm hook
   that runs the migration:

   **CE → newer CE:**

   ```bash
   helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
     --version <new-chart-version> \
     -f values.yaml \
     --set upgrade.upgradeDbSchema=true
   ```

   **PE → newer PE:**

   ```bash
   helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
     --version <new-chart-version> \
     -f /tmp/tbmq-cluster/values-pe.yaml \
     -f values.yaml \
     --set upgrade.upgradeDbSchema=true
   ```

3. **Verify the migration completed.** The migration runs as a Kubernetes Job named
   `my-tbmq-upgrade-<revision>` and is automatically deleted 5 minutes after it finishes
   (`ttlSecondsAfterFinished: 300`). Tail its logs while it runs:

   ```bash
   kubectl logs job/my-tbmq-upgrade-<revision> -n <namespace> -f
   ```

4. **Scale back up.** Because the chart's `replicas` value is unchanged across this upgrade,
   Helm's 3-way merge **preserves the live `replicas: 0`** you set with `kubectl scale` in step 1
   — neither StatefulSet will scale back automatically. Restore both manually after Helm reports
   the upgrade succeeded:

   ```bash
   kubectl scale statefulset/my-tbmq-tbmq-node --replicas=2 -n <namespace>
   # If you also scaled tbmq-ie down in step 1:
   kubectl scale statefulset/my-tbmq-tbmq-ie   --replicas=2 -n <namespace>
   ```

   Use whatever replica counts your deployment runs at — `2` is the chart default.

### CE → PE Upgrade (Cross-Edition Migration)

To migrate an existing CE deployment to PE **on the same TBMQ version**, set
`upgrade.fromVersion=ce` in addition to the standard upgrade flags. This sets the `FROM_VERSION=ce`
env var on the upgrade job (which the PE entrypoint script forwards as
`-Dinstall.upgrade.from_version=ce` to the install application), triggering the PE-specific schema
and data transformations on top of the existing CE data.

```bash
# 1. Scale broker (and IE) to 0
kubectl scale statefulset/my-tbmq-tbmq-node --replicas=0 -n <namespace>
kubectl scale statefulset/my-tbmq-tbmq-ie   --replicas=0 -n <namespace>

# 2. Upgrade with PE overlay AND cross-edition flag
helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f /tmp/tbmq-cluster/values-pe.yaml \
  -f values.yaml \
  --set upgrade.upgradeDbSchema=true \
  --set upgrade.fromVersion=ce
```

What happens during this upgrade:

- The pre-upgrade Job uses the **PE** broker image (because the PE overlay is in effect) with
  `UPGRADE_TB=true` and `FROM_VERSION=ce`. The PE entrypoint script reads `FROM_VERSION` and
  appends `-Dinstall.upgrade.from_version=ce` to the install application command line, which
  switches the migration into CE→PE mode (rewrites the CE schema as PE).
- After the migration succeeds, Helm rolls the `tbmq-node` and `tbmq-ie` StatefulSets onto the PE
  images.
- Manually scale both StatefulSets back to their original replica counts — Helm's 3-way merge
  preserves the live `replicas: 0` you set with `kubectl scale` when the chart's `replicas` value
  is unchanged across the upgrade, so neither StatefulSet scales back automatically:

  ```bash
  kubectl scale statefulset/my-tbmq-tbmq-node --replicas=2 -n <namespace>
  kubectl scale statefulset/my-tbmq-tbmq-ie   --replicas=2 -n <namespace>
  ```

After the migration succeeds, **do not** carry `upgrade.fromVersion=ce` forward to subsequent
PE → PE upgrades — drop the flag (or set it to `""`) on the next `helm upgrade`. Leaving it on
will cause the upgrade job to attempt a CE→PE migration against an already-PE database on every
release, which will fail.

### Upgrading from chart version 1.x to 2.0.0 (TBMQ 2.2.0 → 2.3.0)

Chart version 2.0.0 is a **breaking change**. All Bitnami subchart dependencies (PostgreSQL, Kafka,
Redis Cluster) that earlier chart versions bundled have been removed — the chart now expects you to
bring your own third-party infrastructure. This aligns the Helm deployment with the broader TBMQ
v2.3.0 third-party migration described in the
[official upgrade instructions](https://thingsboard.io/docs/mqtt-broker/install/upgrade-instructions/#third-party-component-updates-in-v230).

#### Why third-party components changed in v2.3.0

TBMQ v2.3.0 moves every third-party component off Bitnami images and onto official open-source
alternatives. The change is the same regardless of how you deploy TBMQ (Docker Compose, raw
manifests, or Helm), but with the Helm chart it also forces a chart-structure change because
chart 1.x bundled those Bitnami images as subcharts and chart 2.0.0 no longer ships them at all.

| Component        | TBMQ v2.2.0 (chart 1.x bundled)       | TBMQ v2.3.0 (chart 2.0.0 — bring your own) |
|------------------|---------------------------------------|--------------------------------------------|
| **PostgreSQL**   | `bitnami/postgresql` (PostgreSQL 16)  | `postgres:17` (operator or self-managed)   |
| **Kafka**        | `bitnamilegacy/kafka:3.7.0` (KRaft)   | `apache/kafka:4.0.0` (official image)      |
| **Redis/Valkey** | `bitnamilegacy/redis:7.2.5` (cluster) | `valkey/valkey:8.0` (Redis-compatible)     |

The motivation (Bitnami catalog changes, image hardening, long-term maintenance) is documented in
the upstream upgrade-instructions page linked above. From the chart's perspective, the result is
that chart 2.0.0 has **no `postgresql:`, `kafka:`, or `redis-cluster:` subchart blocks** — only
top-level `postgresql:`, `kafka:`, and `redis:` connection sections.

#### Two upgrade paths

You have two options when moving from chart 1.x to chart 2.0.0. **Always back up your PostgreSQL
database first**, regardless of which path you choose.

##### Option A — Keep the existing in-cluster Bitnami stack

If your cluster already runs the Bitnami subchart Pods (PostgreSQL, Kafka, Redis Cluster) deployed
by chart 1.x and you want to keep them in place for now, you can detach them from Helm management
and have chart 2.0.0 connect to them as **external** services.

1. **Annotate every Bitnami subchart resource** with `helm.sh/resource-policy: keep` so the
   `helm upgrade` to chart 2.0.0 does **not** delete them. With chart 1.x's default release name
   `my-tbmq-cluster`, the resources to annotate are typically:

   ```bash
   NS=tbmq                  # your namespace
   REL=my-tbmq-cluster      # your release name
   for res in \
     networkpolicy/${REL}-kafka networkpolicy/${REL}-postgresql networkpolicy/${REL}-redis \
     poddisruptionbudget/${REL}-kafka-broker poddisruptionbudget/${REL}-postgresql \
     serviceaccount/${REL}-kafka-provisioning serviceaccount/${REL}-kafka \
     serviceaccount/${REL}-postgresql serviceaccount/${REL}-redis \
     secret/${REL}-kafka-kraft-cluster-id secret/${REL}-postgresql secret/${REL}-redis \
     configmap/${REL}-kafka-controller-configuration configmap/${REL}-kafka-scripts \
     configmap/${REL}-redis-default configmap/${REL}-redis-scripts \
     service/${REL}-kafka-controller-headless service/${REL}-kafka \
     service/${REL}-postgresql-hl service/${REL}-postgresql \
     service/${REL}-redis-headless service/${REL}-redis \
     statefulset/${REL}-kafka-controller statefulset/${REL}-postgresql statefulset/${REL}-redis ; do
     kubectl annotate -n "$NS" "$res" helm.sh/resource-policy=keep --overwrite
   done
   ```

   StatefulSet PVCs are created via `volumeClaimTemplates` and are not in the Helm manifest —
   they survive the upgrade automatically and do not need annotation. Run
   `helm get manifest <release> -n <namespace>` to confirm the exact list of subchart resources in
   your release before running the loop.

2. **Build a `values.yaml` for chart 2.0.0** pointing the new top-level sections at the existing
   in-cluster Bitnami Services. Use the credentials Bitnami already created — do not create new
   Secrets:

   ```yaml
   tbmq:
     image:
       tag: 2.3.0
   tbmq-ie:
     image:
       tag: 2.3.0

   postgresql:
     host: "my-tbmq-cluster-postgresql"
     port: 5432
     database: "thingsboard_mqtt_broker"
     username: "postgres"
     existingSecret: "my-tbmq-cluster-postgresql"
     existingSecretPasswordKey: "postgres-password"

   kafka:
     bootstrapServers: "my-tbmq-cluster-kafka:9092"

   redis:
     connectionType: "cluster"
     nodes: "my-tbmq-cluster-redis-headless:6379"
     usePassword: true
     existingSecret: "my-tbmq-cluster-redis"
     existingSecretPasswordKey: "redis-password"

   loadbalancer:
     type: "nginx"
     http:
       enabled: true
     mqtt:
       enabled: true
   ```

3. **Run the upgrade** with the new chart and the standard upgrade flag:

   ```bash
   helm upgrade my-tbmq-cluster tbmq-helm-chart/tbmq-cluster \
     --version 2.0.0 \
     -f values.yaml \
     --set upgrade.upgradeDbSchema=true \
     -n tbmq
   ```

   Helm will:
   - Run the pre-upgrade Job (`my-tbmq-cluster-upgrade-<rev>`) on the new TBMQ 2.3.0 image. The
     install application logs `Starting TBMQ Upgrade from version 2.2.0 to 2.3.0 ...` and applies
     the schema migration.
   - In-place update the `tbmq-node` and `tbmq-ie` StatefulSets onto the 2.3.0 image
     (selectors and `serviceName` are unchanged across chart versions, so this is a rolling
     restart, not a recreate).
   - Skip the annotated Bitnami StatefulSets / Services / Secrets / etc. — they keep running
     untouched.

4. **Verify**:

   ```bash
   # Pre-upgrade Job log shows the schema migration
   kubectl logs job/my-tbmq-cluster-upgrade-<rev> -n tbmq | grep "Starting TBMQ Upgrade"

   # Broker is on the new image
   kubectl get pod my-tbmq-cluster-tbmq-node-0 -n tbmq \
     -o jsonpath='{.spec.containers[0].image}'   # → thingsboard/tbmq-node:2.3.0

   # Schema bumped
   PGPW=$(kubectl get secret my-tbmq-cluster-postgresql -n tbmq \
     -o jsonpath='{.data.postgres-password}' | base64 -d)
   kubectl exec -n tbmq my-tbmq-cluster-postgresql-0 -- bash -c \
     "PGPASSWORD='$PGPW' psql -U postgres -d thingsboard_mqtt_broker -c \
       'SELECT * FROM tb_schema_settings;'"
   # → schema_version=2003000, product=CE
   ```

5. **Notes / caveats specific to this path:**

   - The chart 1.x `regcred` Secret was rendered unconditionally; chart 2.0.0 only renders it when
     `dockerAuth.username` is set. Helm therefore deletes it on upgrade. The broker still has
     `imagePullSecrets: regcred` in its Pod spec, but Kubernetes only logs a warning and pulls the
     public image normally. Pre-create `regcred` yourself (or set `tbmq.imagePullSecret` to a
     different name) if you actually use a private registry.
   - You are now responsible for the lifecycle of the Bitnami Pods. They are no longer tied to the
     Helm release; future `helm uninstall` will not remove them. Long-term, plan to migrate to the
     official open-source images per the upstream upgrade instructions (Option B).
   - This path keeps the **PostgreSQL major version at 16** (whatever Bitnami shipped in chart 1.x).
     The upstream third-party plan moves new deployments to PostgreSQL 17. Existing data volumes
     are compatible, but a `pg_upgrade` to 17 is the recommended long-term action.

##### Option B — Take backups, provision a fresh third-party stack, restore data

The cleaner long-term path is to move your data onto the v2.3.0 reference third-party stack
(official Postgres 17, Apache Kafka 4.0.0, Valkey 8.0) and let Helm uninstall the old Bitnami
release entirely. The high-level shape — **provided as guidance only, not as a runnable script** —
is:

- **Create full backups** before touching anything: a logical PostgreSQL dump (`pg_dump`) of the
  TBMQ database, plus snapshots of any Kafka/Redis volumes you care about. Note that Kafka and
  Redis state on the old Bitnami volumes is **not directly reusable** with the new images — the
  internal data directories and volume layouts differ — so the practical migration path for those
  two is "start from new, empty volumes and lose in-flight messages / cache." Persisted data lives
  in PostgreSQL.
- **Provision the new third-party stack** outside the Helm release: e.g., the CrunchyData PGO
  operator for PostgreSQL 17, the Strimzi operator for Apache Kafka 4.0.0, and the Valkey Helm
  chart (or any equivalent of your choice). The `tbmq/docs/minikube` guide in this repository
  walks through one such stack on Minikube.
- **Restore the PostgreSQL backup** into the new instance (`pg_restore` or replay the SQL dump).
  Kafka topics are recreated on first connection by TBMQ. Redis is a cache and re-warms naturally.
- **Build a chart 2.0.0 `values.yaml`** that points `postgresql:`, `kafka:`, and `redis:` at your
  newly provisioned services (with their own Secrets), then run the same `helm upgrade` command as
  Option A — the schema migration logic is identical.
- **After verifying the upgraded cluster is healthy**, `helm uninstall` the old chart 1.x release
  cleanly. Because the Bitnami StatefulSets are still part of that old release (Option B does
  **not** annotate them with `keep`), uninstall will tear them down along with their PVCs. Do
  this only after you have confirmed the new stack is the source of truth.

This option is more disruptive but lands you on the supported v2.3.0 third-party baseline. If you
need detailed assistance with the data migration —
[contact ThingsBoard](https://thingsboard.io/docs/contact-us/) for guidance.

### Troubleshooting Upgrades

The pre-upgrade migration Job spawns a Pod named `my-tbmq-upgrade-<revision>-<random>`. The Job
itself has `ttlSecondsAfterFinished: 300`, so both Job and Pod are deleted 5 minutes after the
migration finishes — successful or not. Watch logs while the Job runs, or capture them quickly
once it terminates:

```bash
kubectl logs job/my-tbmq-upgrade-<revision> -n <namespace> -f
# or, if the Pod has already finished:
kubectl logs <upgrade-pod-name> -n <namespace> --previous
```

Common causes:

- **Pod stuck in `Init:0/1` with `wait-for-postgres` repeatedly logging `waiting for postgres`** →
  PostgreSQL is unreachable. The init container runs `until nc -z $host $port; do ... sleep 2; done`,
  which retries silently (no "connection refused" line is printed) and never times out on its own —
  the Helm hook timeout will fire after 600s. Check `postgresql.host`/`postgresql.port` and that
  the DB is reachable from the TBMQ namespace.
- **Authentication failed** → verify `postgresql.password` or that the `existingSecret` contains
  the expected key.
- **Hook timeout (10 minutes)** → for very large databases, the migration may exceed the default
  600s timeout. Roll back (`helm rollback`) and re-run after addressing the performance bottleneck
  (e.g., increase resources, run `VACUUM`/`ANALYZE` first).
- **CE → PE migration failed** → confirm `upgrade.fromVersion=ce` was set AND that the PE image is
  in use (check the upgrade Pod's `image:` field — it should be `thingsboard/tbmq-pe-node:<tag>`).
- **`upgrade.fromVersion=ce` left set on a follow-up PE → PE upgrade** → the upgrade job will try
  to migrate an already-PE database from CE and fail. Drop the flag.

## Runtime Troubleshooting

Symptoms you may hit on a running cluster (separate from the upgrade-time issues covered in
[Troubleshooting Upgrades](#troubleshooting-upgrades) above).

### Broker exits immediately with `License Error GENERAL_ERROR(300)`

The broker logs:

```
ERROR o.t.m.b.d.s.BasicSubscriptionService - License secret is not provided!
ERROR o.t.m.b.d.s.BasicSubscriptionService - Please provide license.secret property value in thingsboard-mqtt-broker.yml or set TBMQ_LICENSE_SECRET environment variable!
INFO  o.t.m.b.d.s.BasicSubscriptionService - Terminating application due to critical License Error GENERAL_ERROR(300), exit code [-1]
```

PE images require a license value. Either set `license.secret` inline or pre-create a Secret and
point `license.existingSecret` at it (see [PE install — Provide your license](#1-provide-your-license)).
CE images don't need a license — confirm you didn't pull the PE images (`thingsboard/tbmq-pe-*`)
without configuring one.

### MQTT clients get `Connection Refused: not authorised` (return code 5)

No MQTT client credentials have been provisioned. TBMQ 2.3.0 ships with **no enabled MQTT auth
providers by default**, and there is no env var to enable basic auth — credentials and provider
state are managed exclusively through the admin REST API
(`POST /api/mqtt/client/credentials`, after `POST /api/auth/login` as sysadmin). See the
[TBMQ documentation](https://thingsboard.io/docs/mqtt-broker/) for the full provider model.

### Broker crash-loops with `License Error: CLUSTER_ID_MISMATCH(114)`

The license server has bound your TBMQ license to a different cluster id than the one this broker
is presenting. Common causes:

- **Persistence disabled and Pod recreated.** Without `tbmq.persistence.enabled=true`, `/data` is
  an `emptyDir` and the per-pod instance-data file (`/data/tbmq-instance-license-$(TB_SERVICE_ID).data`)
  is wiped on every restart. The broker generates a new cluster id on the next start, but the
  license server still holds the previous binding and rejects the new one. Re-enable
  `tbmq.persistence` (the chart default).
- **PVC was deleted between installs.** `kubectl delete pvc` (or `kubectl delete namespace`) wipes
  the instance-data file. Deactivate the prior binding via your license-server admin before
  reinstalling, or your fresh cluster id will collide with the previous one.
- **License is bound to another TBMQ deployment.** Single-bind licenses can only activate against
  one cluster id at a time. Deactivate the prior binding (or contact ThingsBoard) before installing
  into a new cluster.

## Configuration Reference

### Global Parameters

| Parameter                    | Description                                                                                                                                                                          | Default                     |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|
| **Docker Authentication**    |                                                                                                                                                                                      |                             |
| dockerAuth.registry          | Docker registry for TBMQ images. Used only when supplying credentials.                                                                                                               | https://index.docker.io/v1/ |
| dockerAuth.username          | Docker username. When set, the chart creates a pull Secret named `tbmq.imagePullSecret` (default `regcred`). When empty, no Secret is created — useful when you pre-create your own. | ""                          |
| dockerAuth.password          | Docker password. Used together with `dockerAuth.username` to populate the chart-managed pull Secret.                                                                                 | ""                          |
| **Installation**             |                                                                                                                                                                                      |                             |
| installation.installDbSchema | Initializes the TBMQ DB schema. Pass via `--set` on first install only. The post-install hook is also bound to `post-upgrade` for recovery scenarios.                                | false                       |
| installation.argocd          | Replaces Helm install/upgrade hooks with ArgoCD `Sync` hook annotations on the install pod.                                                                                          | false                       |
| **Upgrade**                  |                                                                                                                                                                                      |                             |
| upgrade.upgradeDbSchema      | Runs the DB migration during `helm upgrade` (pre-upgrade hook). Ignored on first install.                                                                                            | false                       |
| upgrade.argocd               | Replaces Helm pre-upgrade hooks with ArgoCD `PreSync` hook annotations on the upgrade job.                                                                                           | false                       |
| upgrade.fromVersion          | Edition the upgrade is migrating FROM. Set to `"ce"` only for CE → PE cross-edition upgrades. Leave empty for same-edition upgrades.                                                 | ""                          |
| **License (PE only)**        | Required for PE; ignored for CE (when both `secret` and `existingSecret` are empty, the chart skips license wiring).                                                                 |                             |
| license.secret               | License value. When set, the chart creates a Secret `<release>-tbmq-license-secret`. Convenient for testing; the value lands in the helm release manifest.                           | ""                          |
| license.existingSecret       | Name of a pre-existing Kubernetes Secret holding the license. Recommended for production. When set, the chart does NOT create a Secret of its own.                                   | ""                          |
| license.existingSecretLicenseKey | Key inside `existingSecret` that holds the license value. Matches the convention from the official PE k8s manifests.                                                             | "license-key"               |
| license.instanceDataFile     | Path to the per-pod license cache file. Default uses `$(TB_SERVICE_ID)` so each replica gets its own file under `/data`, which is PVC-backed by default (see `tbmq.persistence`).      | "/data/tbmq-instance-license-$(TB_SERVICE_ID).data" |

### TBMQ (Broker) Parameters

| Parameter                               | Description                                                                                                                                                | Default                                 |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| **Image**                               |                                                                                                                                                            |                                       |
| tbmq.image.repository                   | Broker image repository. CE: `thingsboard/tbmq-node`. PE (via `values-pe.yaml`): `thingsboard/tbmq-pe-node`.                                              | thingsboard/tbmq-node                 |
| tbmq.image.tag                          | Image tag. CE default tracks the chart `appVersion`. PE pins `<appVersion>PE` via `values-pe.yaml`.                                                        | 2.3.0                                 |
| tbmq.imagePullSecret                    | Pull secret name referenced by the broker StatefulSet, install Pod, and upgrade Job. Auto-created from `dockerAuth.username`/`password` if those are set; otherwise expected to exist in the namespace already. | regcred                               |
| tbmq.imagePullPolicy                    | Image pull policy.                                                                                                                                         | Always                                |
| **Scaling**                             |                                                                                                                                                            |                                       |
| tbmq.statefulSet.replicas               | Number of broker pods. With one replica, broker runs in singleton mode (`TB_SERVICE_SINGLETON_MODE=true`).                                                 | 2                                     |
| tbmq.statefulSet.annotations            | Annotations applied to the StatefulSet resource (CI/CD, audit, etc.).                                                                                      | { }                                   |
| tbmq.annotations                        | Annotations applied to broker pods (Prometheus scrape, sidecars, etc.).                                                                                    | { }                                   |
| tbmq.nodeSelector / tbmq.affinity       | Pod scheduling rules.                                                                                                                                      | { }                                   |
| tbmq.restartPolicy                      | Pod restart policy.                                                                                                                                        | Always                                |
| **Ports**                               |                                                                                                                                                            |                                       |
| tbmq.ports                              | Container ports: HTTP 8083, MQTT 1883, MQTTS 8883, MQTT-WS 8084, MQTT-WSS 8085.                                                                            | (see values.yaml)                     |
| **Configuration**                       |                                                                                                                                                            |                                       |
| tbmq.customEnv                          | Map of env vars applied to broker pods, install Pod, and upgrade Job. Wins over keys in any `existing*ConfigMap`.                                          | { }                                   |
| tbmq.existingConfigMap                  | One ConfigMap providing both `conf` (Java opts) and `logback` (logging) keys. Highest priority — when set, the chart skips rendering its default ConfigMaps and ignores the two below. Applies to broker pods and the upgrade Job; the install Pod uses a dedicated minimal `*-install-config`. | ""                                    |
| tbmq.existingJavaOptsConfigMap          | ConfigMap with a `conf` key providing Java options. Used only when `existingConfigMap` is empty.                                                           | ""                                    |
| tbmq.existingLogbackConfigMap           | ConfigMap with a `logback` key providing logback XML. Used only when `existingConfigMap` is empty.                                                          | ""                                    |
| tbmq.enableChecksumAnnotations          | Auto-restart pods on relevant ConfigMap/Secret changes during `helm upgrade`. Logback is intentionally excluded — TBMQ hot-reloads logback every 10s.       | true                                  |
| **Health checks**                       |                                                                                                                                                            |                                       |
| tbmq.readinessProbe                     | Default: TCP 1883, initialDelay 30s, period 20s, failure threshold 5.                                                                                      | (see values.yaml)                     |
| tbmq.livenessProbe                      | Default: TCP 1883, initialDelay 60s, period 10s, failure threshold 10.                                                                                     | (see values.yaml)                     |
| **Security & resources**                |                                                                                                                                                            |                                       |
| tbmq.securityContext                    | Defaults: `runAsUser: 799`, `runAsNonRoot: true`, `fsGroup: 799`.                                                                                          | (see values.yaml)                     |
| tbmq.resources                          | CPU/memory requests and limits. Set explicitly for production.                                                                                             | { }                                   |
| **Persistence**                         |                                                                                                                                                            |                                       |
| tbmq.persistence.enabled                | Back the broker `/data` directory with a per-pod PVC (via `volumeClaimTemplate`). Required for PE so the license instance-data file survives Pod recreation; safe to leave on for CE. | true |
| tbmq.persistence.size                   | PVC size. The PE license cache file is a few KB; 1Gi just leaves headroom for any future PE feature that may write to `/data`. The reference PE Kubernetes manifests request 100Mi — bumping this default does not affect compatibility. | "1Gi"                                 |
| tbmq.persistence.storageClassName       | StorageClass name. Empty means use the cluster's default StorageClass.                                                                                       | ""                                    |
| tbmq.persistence.accessModes            | PVC access modes. ReadWriteOnce is correct for per-pod claims.                                                                                              | ["ReadWriteOnce"]                     |

### TBMQ Integration Executor Parameters

The `tbmq-ie` parameters mirror `tbmq` parameters above. Notable differences:

| Parameter                       | Description                                                                                                                                                | Default                               |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| tbmq-ie.image.repository        | IE image. CE: `thingsboard/tbmq-integration-executor`. PE (via overlay): `thingsboard/tbmq-pe-integration-executor`.                                       | thingsboard/tbmq-integration-executor |
| tbmq-ie.image.tag               | Image tag. CE default tracks the chart `appVersion`. PE pins `<appVersion>PE` via `values-pe.yaml`.                                                         | 2.3.0                                 |
| tbmq-ie.imagePullSecret         | Pull secret name referenced by the IE StatefulSet only — independent of `tbmq.imagePullSecret`. The chart auto-creates **only one** Secret (named after `tbmq.imagePullSecret`, when `dockerAuth.username` is set). If `tbmq-ie.imagePullSecret` differs, pre-create that Secret yourself. | regcred                               |
| tbmq-ie.imagePullPolicy         | Image pull policy.                                                                                                                                          | Always                                |
| tbmq-ie.statefulSet.replicas    | Number of IE pods.                                                                                                                                          | 2                                     |
| tbmq-ie.ports                   | HTTP 8082.                                                                                                                                                 |                                       |
| tbmq-ie.readinessProbe          | Default: TCP `http`, period 20s.                                                                                                                            |                                       |
| tbmq-ie.livenessProbe           | Default: TCP `http`, initialDelay 120s, period 20s.                                                                                                         |                                       |

> All other `tbmq-ie.*` keys mirror their `tbmq.*` counterparts with the same defaults and behavior:
> `statefulSet.annotations`, `annotations`, `nodeSelector`, `affinity`, `customEnv`,
> `existingConfigMap`, `existingJavaOptsConfigMap`, `existingLogbackConfigMap`,
> `enableChecksumAnnotations`, `restartPolicy`, `securityContext`, `resources`. The IE Pod does
> **not** mount PostgreSQL, Redis, or PE license env vars — it only connects to Kafka.

> **Note:** `tbmq-ie` is referenced in templates with `index .Values "tbmq-ie"` because of the
> hyphen in the key name. The hyphen does not need escaping on the command line — use the
> dotted path directly: `--set tbmq-ie.statefulSet.replicas=3`.

### Persistence

The broker StatefulSet provisions a per-pod PVC for `/data` via `volumeClaimTemplate`.
This is required for **Professional Edition** deployments because the license client
writes a per-pod instance-data file (`/data/tbmq-instance-license-$(TB_SERVICE_ID).data`)
that the license server uses to identify each broker instance — losing the file on
Pod recreation causes the broker to re-register as a fresh instance and counts toward
your license slot pool.

For Community Edition, nothing meaningful is persisted under `/data`, so disabling
persistence is safe:

```yaml
tbmq:
  persistence:
    enabled: false
```

The Integration Executor StatefulSet and the pre-upgrade Job continue to use `emptyDir`
for `/data` — they don't carry per-instance state. The install Pod doesn't mount `/data`
at all (its only volumes are the install ConfigMap and a logs `emptyDir`).

**Cleanup.** `helm uninstall` does **not** delete PVCs created by `volumeClaimTemplate`.
The chart-managed PVCs are named `<release>-tbmq-node-data-<release>-tbmq-node-<ordinal>`
(one per broker replica) and carry no `app=...` label, so reap them by name pattern:

```bash
kubectl get pvc -n <namespace> -o name | grep tbmq-node-data \
  | xargs -r kubectl delete -n <namespace>
```

Or simply `kubectl delete namespace <namespace>` if you no longer need the data.

## Infrastructure Configuration

### PostgreSQL

| Parameter                              | Description                                                                                  | Default                   |
|----------------------------------------|----------------------------------------------------------------------------------------------|---------------------------|
| postgresql.host                        | PostgreSQL hostname or service name.                                                         | ""                        |
| postgresql.port                        | PostgreSQL port.                                                                             | 5432                      |
| postgresql.database                    | Database name. Must exist before install (the chart creates the schema, not the database).  | "thingsboard_mqtt_broker" |
| postgresql.username                    | PostgreSQL username.                                                                         | "postgres"                |
| postgresql.password                    | PostgreSQL password. Ignored if `existingSecret` is set. Stored in a chart-managed Secret.   | ""                        |
| postgresql.existingSecret              | Name of an existing Secret holding the password. Recommended for production.                | ""                        |
| postgresql.existingSecretPasswordKey   | Key inside `existingSecret` that holds the password.                                         | ""                        |

```yaml
postgresql:
  host: "my-postgres.example.com"
  port: 5432
  database: "thingsboard_mqtt_broker"
  username: "postgres"
  existingSecret: "my-pg-secret"
  existingSecretPasswordKey: "password"
```

### Kafka

| Parameter              | Description                                                | Default |
|------------------------|------------------------------------------------------------|---------|
| kafka.bootstrapServers | Comma-separated `host:port` list of Kafka bootstrap nodes. | ""      |

```yaml
kafka:
  bootstrapServers: "kafka-0:9092,kafka-1:9092,kafka-2:9092"
```

### Redis / Valkey / Cache

TBMQ speaks the Redis protocol. Any Redis-compatible backend (Redis, Valkey, Dragonfly, KeyDB)
works. Two connection modes are supported.

| Parameter                       | Description                                                                                              | Default    |
|---------------------------------|----------------------------------------------------------------------------------------------------------|------------|
| redis.connectionType            | `"standalone"` (single-node) or `"cluster"` (Redis Cluster).                                             | "cluster"  |
| redis.host                      | Hostname for `standalone` mode.                                                                          | ""         |
| redis.port                      | Port for `standalone` mode.                                                                              | 6379       |
| redis.nodes                     | Comma-separated `host:port` list for `cluster` mode.                                                     | ""         |
| redis.usePassword               | Whether the cache requires password authentication.                                                      | true       |
| redis.password                  | Password. Ignored if `existingSecret` is set. Stored in a chart-managed Secret.                          | ""         |
| redis.existingSecret            | Name of an existing Secret holding the password.                                                         | ""         |
| redis.existingSecretPasswordKey | Key inside `existingSecret` that holds the password.                                                     | ""         |

**Cluster mode:**

```yaml
redis:
  connectionType: "cluster"
  nodes: "redis-0:6379,redis-1:6379,redis-2:6379,redis-3:6379,redis-4:6379,redis-5:6379"
  existingSecret: "my-redis-secret"
  existingSecretPasswordKey: "redis-password"
```

**Standalone mode (e.g., single-node Valkey):**

```yaml
redis:
  connectionType: "standalone"
  host: "valkey.example.com"
  port: 6379
  usePassword: false
```

In `cluster` mode, the chart automatically renders cluster-only keys (`REDIS_NODES`,
`REDIS_MAX_REDIRECTS`, `REDIS_CLUSTER_USE_DEFAULT_POOL_CONFIG`, and the Lettuce/Jedis topology
refresh tunables) into the Redis ConfigMap; in `standalone` mode those keys are omitted and only
`REDIS_HOST`/`REDIS_PORT` are set.

## Load Balancer

The chart creates Kubernetes `Ingress` (for HTTP) and `Service` (for MQTT) resources. It does
**not** deploy the load balancer or ingress controller itself — those must already exist in your
cluster (NGINX Ingress Controller, AWS Load Balancer Controller, Application Gateway Ingress
Controller, etc.).

| Parameter                                               | Description                                                                                              | Default                |
|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------|------------------------|
| loadbalancer.type                                       | Provider flavor: `"nginx"`, `"aws"`, `"azure"`, `"gcp"`. Selects template variant + default annotations. | "nginx"                |
| loadbalancer.http.enabled                               | Create the HTTP Ingress.                                                                                 | true                   |
| loadbalancer.http.annotations                           | Extra Ingress annotations. Merged with provider defaults — user values win on conflict.                  | { }                    |
| loadbalancer.http.ssl.enabled                           | Enable HTTPS termination at the load balancer.                                                           | false                  |
| loadbalancer.http.ssl.certificateRef                    | Cert reference: AWS ACM ARN, Azure `appgw-ssl-certificate` value, GCP `ManagedCertificate` name.        | ""                     |
| loadbalancer.http.ssl.domains                           | Domains for HTTPS. Required for GCP `ManagedCertificate`.                                                | ["www.example.com"]    |
| loadbalancer.http.ssl.staticIP                          | GCP-only: static IP name for the HTTP(S) load balancer.                                                  | "tbmq-http-lb-address" |
| loadbalancer.mqtt.enabled                               | Create the MQTT LoadBalancer Service.                                                                    | true                   |
| loadbalancer.mqtt.annotations                           | Extra Service annotations. Merged with provider defaults — user values win on conflict.                  | { }                    |
| loadbalancer.mqtt.mutualTls.enabled                     | Enable application-level mTLS. Requires server cert + key. Disables `tlsTermination`.                    | false                  |
| loadbalancer.mqtt.mutualTls.configMapName               | ConfigMap with `server.pem` and `mqttserver_key.pem` keys.                                               | "tbmq-node-mqtts-config" |
| loadbalancer.mqtt.mutualTls.privateKeyPasswordSecret    | Optional Secret holding the private key password.                                                        | ""                     |
| loadbalancer.mqtt.mutualTls.privateKeyPasswordSecretKey | Key inside the Secret with the private key password.                                                     | "key_password"         |
| loadbalancer.mqtt.tlsTermination.enabled                | Enable L4 TLS termination at the load balancer. Supported on AWS NLB only. Ignored if mTLS is enabled.   | false                  |
| loadbalancer.mqtt.tlsTermination.certificateRef         | AWS NLB ACM certificate ARN.                                                                             | ""                     |

## Mutual TLS (mTLS) for MQTT

To enable application-level mTLS for the MQTT listener:

1. Create a ConfigMap holding the server certificate and private key:

   ```bash
   kubectl create configmap tbmq-node-mqtts-config \
     --from-file=server.pem=/path/to/server.pem \
     --from-file=mqttserver_key.pem=/path/to/mqttserver_key.pem \
     -o yaml --dry-run=client | kubectl apply -f -
   ```

2. (Optional) If the private key is password-protected, create a Secret:

   ```bash
   kubectl create secret generic mqtt-tls-secret \
     --from-literal=key_password="YOUR_KEY_PASSWORD" \
     -o yaml --dry-run=client | kubectl apply -f -
   ```

3. Enable mTLS in your `values.yaml`:

   ```yaml
   loadbalancer:
     mqtt:
       enabled: true
       mutualTls:
         enabled: true
         configMapName: "tbmq-node-mqtts-config"
         privateKeyPasswordSecret: "mqtt-tls-secret"      # omit if not needed
         privateKeyPasswordSecretKey: "key_password"      # omit if not needed
   ```

## Uninstalling

```bash
helm uninstall my-tbmq -n <namespace>
```

`helm uninstall` removes the Kubernetes resources owned by the release (StatefulSets, Services,
ConfigMaps, chart-managed Secrets, Ingress, and the load balancer Service). It does **not** touch:

- **External infrastructure** — PostgreSQL data, Kafka topics, and Redis cache are owned by the
  systems you deployed alongside TBMQ. Drop them explicitly if you no longer need them.
- **Pre-existing Secrets** — anything referenced via `postgresql.existingSecret`,
  `redis.existingSecret`, or a pre-created `tbmq.imagePullSecret` is left in place.
- **Per-pod PVCs created from `volumeClaimTemplate`** — chart-managed `tbmq-node-data` PVCs are not deleted by `helm uninstall`. They carry no `app=...` label (the volumeClaimTemplate has none), so drop them explicitly by name pattern: `kubectl get pvc -n <namespace> -o name | grep tbmq-node-data | xargs -r kubectl delete -n <namespace>`, or just delete the whole namespace.
