# Helm Chart for TBMQ Cluster

TBMQ is an open-source MQTT message broker capable of handling 4M+ concurrent client connections,
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
- Helm hooks for one-shot install and upgrade jobs that run TBMQ's database schema initializer or
  migration tool.
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
- `redis.connectionType` plus either `redis.host`/`redis.port` (standalone) or `redis.nodes` (cluster), and credentials if `usePassword: true`

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
  (`/data/tbmq-instance-license-$(TB_SERVICE_ID).data`) places it on the chart's `/data` emptyDir
  and namespaces it by pod name so multi-replica deployments don't race on a single file. Override
  via `license.instanceDataFile` only if you mount a different writable path.

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
kubectl get pods -l app.kubernetes.io/instance=my-tbmq -n <namespace>
```

The install pod (`my-tbmq-install-pod`) runs once, creates the schema, then exits. Helm deletes it
immediately on completion (`hook-delete-policy: hook-succeeded,hook-failed`), so capture logs while
the pod is still alive — the install hook has a 300s timeout. The `my-tbmq-tbmq-node-*` and
`my-tbmq-tbmq-ie-*` StatefulSet pods should reach `Running` and pass readiness probes within a
minute or two after the install pod succeeds.

```bash
kubectl logs my-tbmq-install-pod -n <namespace> -f
```

If the pod is gone before you can grab logs, re-run the install with `--debug` so Helm streams hook
output to your terminal, or inspect the broker pod logs after they crash-loop on the missing
schema.

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

When `enableChecksumAnnotations: true` (the default), pods automatically restart on `helm upgrade`
when any of the following change:

- Java options ConfigMap (`conf` key)
- Custom env ConfigMap (`tbmq.customEnv` / `tbmq-ie.customEnv`)
- PostgreSQL connection ConfigMap and Secret
- Redis connection ConfigMap and Secret
- Kafka connection ConfigMap

Logback ConfigMap changes do **not** trigger restart. TBMQ is configured with
`<configuration scan="true" scanPeriod="10 seconds">` and picks up logback changes within ~10
seconds of the ConfigMap propagating to the pod.

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
   # Recommended on minor/major upgrades that touch IE-related tables:
   kubectl scale statefulset/my-tbmq-tbmq-ie   --replicas=0 -n <namespace>
   ```

   Scaling `tbmq-ie` is optional for routine config-only changes but recommended whenever a schema
   migration runs (the IE talks to the same database).

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

4. **Scale back up.** Helm scales the StatefulSets back to their configured replica counts as part
   of the upgrade — no manual scale-up is needed unless you scaled down outside of Helm. If you
   manually scaled `tbmq-ie` to 0 in step 1, scale it back:

   ```bash
   kubectl scale statefulset/my-tbmq-tbmq-ie --replicas=2 -n <namespace>
   ```

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
- Manually scale `tbmq-ie` back up if you scaled it down.

After the migration succeeds, **do not** carry `upgrade.fromVersion=ce` forward to subsequent
PE → PE upgrades — drop the flag (or set it to `""`) on the next `helm upgrade`. Leaving it on
will cause the upgrade job to attempt a CE→PE migration against an already-PE database on every
release, which will fail.

### Upgrading from chart version 1.x to 2.0.0

Chart version 2.0.0 is a **breaking change**: all Bitnami subchart dependencies (PostgreSQL, Redis
Cluster, Kafka) have been removed. The chart now requires you to bring your own infrastructure.

**Migration steps:**

1. Deploy your replacement PostgreSQL, Kafka, and Redis/Valkey instances and verify connectivity
   from the TBMQ namespace.
2. Migrate data from the old Bitnami-deployed PostgreSQL into your new PostgreSQL (logical dump and
   restore). Kafka topics are recreated on first connection — no data migration is needed if you
   are willing to lose in-flight messages. Redis cache contents are ephemeral and do not need
   migration.
3. Update your `values.yaml`:
   - Remove the `postgresql:`, `redis-cluster:`, `kafka:`, `externalPostgresql:`, `externalKafka:`,
     and `external-redis-cluster:` sections.
   - Add the new top-level `postgresql:`, `kafka:`, and `redis:` sections with your new connection
     details. See [Infrastructure Configuration](#infrastructure-configuration).
4. Scale `tbmq-node` to 0 and run the upgrade as documented above.
5. After verifying the upgraded cluster is healthy, you can `helm uninstall` the old Bitnami
   subcharts (if they were managed by Helm separately).

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

- **Connection refused** to PostgreSQL → check `postgresql.host`/`postgresql.port` and that the DB
  is reachable from the TBMQ namespace. The Job's `wait-for-postgres` init container loops until
  the host:port is reachable (it never times out on its own; the Helm hook timeout will fire after
  600s).
- **Authentication failed** → verify `postgresql.password` or that the `existingSecret` contains
  the expected key.
- **Hook timeout (10 minutes)** → for very large databases, the migration may exceed the default
  600s timeout. Roll back (`helm rollback`) and re-run after addressing the performance bottleneck
  (e.g., increase resources, run `VACUUM`/`ANALYZE` first).
- **CE → PE migration failed** → confirm `upgrade.fromVersion=ce` was set AND that the PE image is
  in use (check the upgrade Pod's `image:` field — it should be `thingsboard/tbmq-pe-node:<tag>`).
- **`upgrade.fromVersion=ce` left set on a follow-up PE → PE upgrade** → the upgrade job will try
  to migrate an already-PE database from CE and fail. Drop the flag.

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
| license.instanceDataFile     | Path to the per-pod license cache file. Default uses `$(TB_SERVICE_ID)` so each replica gets its own file under the chart's `/data` emptyDir.                                        | "/data/tbmq-instance-license-$(TB_SERVICE_ID).data" |

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
| tbmq.ports                              | Container ports: HTTP 8083, HTTPS 443, MQTT 1883, MQTTS 8883, MQTT-WS 8084, MQTT-WSS 8085.                                                                 | (see values.yaml)                     |
| **Configuration**                       |                                                                                                                                                            |                                       |
| tbmq.customEnv                          | Map of env vars applied to broker pods, install Pod, and upgrade Job. Wins over keys in any `existing*ConfigMap`.                                          | { SECURITY_MQTT_BASIC_ENABLED: "true" } |
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

### TBMQ Integration Executor Parameters

The `tbmq-ie` parameters mirror `tbmq` parameters above. Notable differences:

| Parameter                       | Description                                                                                                                                                | Default                               |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| tbmq-ie.image.repository        | IE image. CE: `thingsboard/tbmq-integration-executor`. PE (via overlay): `thingsboard/tbmq-pe-integration-executor`.                                      | thingsboard/tbmq-integration-executor |
| tbmq-ie.image.tag               | Image tag. CE default tracks the chart `appVersion`. PE pins `<appVersion>PE` via `values-pe.yaml`.                                                         | 2.3.0                                 |
| tbmq-ie.statefulSet.replicas    | Number of IE pods.                                                                                                                                          | 2                                     |
| tbmq-ie.ports                   | HTTP 8082.                                                                                                                                                 |                                       |
| tbmq-ie.readinessProbe          | Default: TCP `http`, period 20s.                                                                                                                            |                                       |
| tbmq-ie.livenessProbe           | Default: TCP `http`, initialDelay 120s, period 20s.                                                                                                         |                                       |

> **Note:** `tbmq-ie` is referenced in templates with `index .Values "tbmq-ie"` because of the
> hyphen in the key name. When overriding via `--set`, escape the dot path:
> `--set tbmq-ie.statefulSet.replicas=3`.

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

In `cluster` mode, the chart automatically renders Lettuce/Jedis topology refresh settings into the
Redis ConfigMap; in `standalone` mode those settings are omitted.

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

The broker and IE pods use `emptyDir` for logs and node-local data, so there are no PVCs created
by this chart to clean up.
