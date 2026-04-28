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

The PE images (`thingsboard/tbmq-pe-node` and `thingsboard/tbmq-pe-integration-executor`) are
selected by applying the bundled `values-pe.yaml` overlay. The overlay is shipped inside the chart
package, so first extract it to a local path:

```bash
helm pull tbmq-helm-chart/tbmq-cluster --untar --untardir /tmp
```

Then install with the overlay applied **before** your own `values.yaml`, so your overrides win on
conflict:

```bash
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

> **Tip:** `my-tbmq` is the **Helm release name**. Pick any name. It is used as the prefix for all
> deployed resources and as the reference for future `helm` commands against this release.

### Step 4: Verify the Install

```bash
kubectl get pods -l app.kubernetes.io/instance=my-tbmq -n <namespace>
```

The install pod (`my-tbmq-install-pod`) runs once and creates the schema, then exits. The
`my-tbmq-tbmq-node-*` and `my-tbmq-tbmq-ie-*` StatefulSet pods should reach `Running` and pass
readiness probes within a minute or two.

If the install pod fails, inspect its logs (it has a 5-minute TTL after completion):

```bash
kubectl logs my-tbmq-install-pod -n <namespace>
```

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

1. **Scale `tbmq-node` to 0 replicas** so no broker is connected to PostgreSQL while the schema
   migration runs:

   ```bash
   kubectl scale statefulset/my-tbmq-tbmq-node --replicas=0 -n <namespace>
   ```

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

3. **Verify the migration completed.** The migration job runs as
   `my-tbmq-upgrade-<revision>-<random>` and is automatically cleaned up 5 minutes after success
   (`ttlSecondsAfterFinished: 300`). Check its logs promptly if anything looks off:

   ```bash
   kubectl logs job/my-tbmq-upgrade-<revision> -n <namespace>
   ```

4. **Scale `tbmq-node` back up.** Helm scales the StatefulSet back to the configured replica count
   automatically when the upgrade hook completes — no manual scale-up is needed unless you scaled
   down outside of Helm.

### CE → PE Upgrade (Cross-Edition Migration)

To migrate an existing CE deployment to PE on the same TBMQ version, set `upgrade.fromVersion=ce`
in addition to the standard upgrade flags. This passes `-Dinstall.upgrade.from_version=ce` to the
upgrade job, which applies PE-specific schema and data transformations on top of the existing CE
data.

```bash
# 1. Scale broker to 0
kubectl scale statefulset/my-tbmq-tbmq-node --replicas=0 -n <namespace>

# 2. Upgrade with PE overlay AND cross-edition flag
helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f /tmp/tbmq-cluster/values-pe.yaml \
  -f values.yaml \
  --set upgrade.upgradeDbSchema=true \
  --set upgrade.fromVersion=ce
```

After the migration succeeds, do **not** carry `upgrade.fromVersion=ce` forward to subsequent
PE → PE upgrades. Drop the flag (or set it to `""`) on the next `helm upgrade`.

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

The pre-upgrade migration job creates a temporary pod named
`my-tbmq-upgrade-<revision>-<random>`. If the upgrade fails (CrashLoopBackOff or hook timeout),
inspect the pod logs immediately — it is auto-deleted 5 minutes after completion:

```bash
kubectl logs <upgrade-pod-name> -n <namespace>
```

Common causes:

- **Connection refused** to PostgreSQL → check `postgresql.host`/`postgresql.port` and that the DB
  is reachable from the TBMQ namespace.
- **Authentication failed** → verify `postgresql.password` or that the `existingSecret` contains
  the expected key.
- **Hook timeout (10 minutes)** → for very large databases, the migration may exceed the default
  600s timeout. Re-run with a fresh release revision after addressing performance.
- **CE → PE migration failed** → confirm `upgrade.fromVersion=ce` was set AND that the PE image is
  in use (check the upgrade pod's `image:` field).

## Configuration Reference

### Global Parameters

| Parameter                    | Description                                                                                                                                                                          | Default                     |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|
| **Docker Authentication**    |                                                                                                                                                                                      |                             |
| dockerAuth.registry          | Docker registry for TBMQ images. Used only when supplying credentials.                                                                                                               | https://index.docker.io/v1/ |
| dockerAuth.username          | Docker username — written to the `regcred` pull secret.                                                                                                                              | ""                          |
| dockerAuth.password          | Docker password — written to the `regcred` pull secret.                                                                                                                              | ""                          |
| **Installation**             |                                                                                                                                                                                      |                             |
| installation.installDbSchema | Initializes the TBMQ DB schema. Pass via `--set` on first install only. The post-install hook is also bound to `post-upgrade` for recovery scenarios.                                | false                       |
| installation.argocd          | Replaces Helm install/upgrade hooks with ArgoCD `Sync` hook annotations on the install pod.                                                                                          | false                       |
| **Upgrade**                  |                                                                                                                                                                                      |                             |
| upgrade.upgradeDbSchema      | Runs the DB migration during `helm upgrade` (pre-upgrade hook). Ignored on first install.                                                                                            | false                       |
| upgrade.argocd               | Replaces Helm pre-upgrade hooks with ArgoCD `PreSync` hook annotations on the upgrade job.                                                                                           | false                       |
| upgrade.fromVersion          | Edition the upgrade is migrating FROM. Set to `"ce"` only for CE → PE cross-edition upgrades. Leave empty for same-edition upgrades.                                                 | ""                          |

### TBMQ (Broker) Parameters

| Parameter                               | Description                                                                                                                                                | Default                                 |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| **Image**                               |                                                                                                                                                            |                                       |
| tbmq.image.repository                   | Broker image repository. CE: `thingsboard/tbmq-node`. PE (via `values-pe.yaml`): `thingsboard/tbmq-pe-node`.                                              | thingsboard/tbmq-node                 |
| tbmq.image.tag                          | Image tag. Defaults to the chart `appVersion`.                                                                                                             | 2.2.0                                 |
| tbmq.imagePullSecret                    | Pull secret name. Auto-created from `dockerAuth` if credentials are provided.                                                                              | regcred                               |
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
| tbmq.customEnv                          | Map of env vars added to broker pods, install pod, and upgrade job. Wins over keys in any `existing*ConfigMap`.                                            | { SECURITY_MQTT_BASIC_ENABLED: "true" } |
| tbmq.existingConfigMap                  | One ConfigMap providing both `conf` (Java opts) and `logback` (logging) keys. Highest priority — disables the two below.                                   | ""                                    |
| tbmq.existingJavaOptsConfigMap          | ConfigMap with a `conf` key providing Java options.                                                                                                        | ""                                    |
| tbmq.existingLogbackConfigMap           | ConfigMap with a `logback` key providing logback XML.                                                                                                      | ""                                    |
| tbmq.enableChecksumAnnotations          | Auto-restart pods on relevant ConfigMap/Secret changes during `helm upgrade`. Logback is excluded (hot-reloaded).                                          | true                                  |
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
| tbmq-ie.image.tag               | Image tag. Defaults to chart `appVersion`.                                                                                                                 | 2.2.0                                 |
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

`helm uninstall` removes Kubernetes resources but **does not delete persistent data**. The TBMQ
StatefulSets use `emptyDir` volumes for logs and node-local data — those are deleted when pods
terminate. PostgreSQL, Kafka, and Redis data are owned by your external infrastructure and remain
untouched.

If you used the chart's checksum-restart feature with PVCs added externally, you can clean them up
explicitly:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=my-tbmq -n <namespace>
```
