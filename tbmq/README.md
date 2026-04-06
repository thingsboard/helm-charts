# Helm Chart for TBMQ Cluster

TBMQ represents an open-source MQTT message broker with the capacity to handle 4M+ concurrent client connections, 
supporting a minimum of 3M messages per second throughput per single cluster node with low latency delivery. 
In the cluster mode, its capabilities are further enhanced, enabling it to support more than 100M concurrently connected clients.

**Documentation & Resources:**

 - TBMQ [Documentation](https://thingsboard.io/products/mqtt-broker/)
 - TBMQ GitHub [Repository](https://github.com/thingsboard/tbmq)
 - ThingsBoard Charts GitHub [Repository](https://github.com/thingsboard/helm-charts)

> **Trademarks:** This software listing is packaged by TBMQ Team. 
The respective trademarks mentioned in the offering are owned by the respective companies, and use of them does not imply any affiliation or endorsement.

## Introduction

This chart bootstraps a TBMQ deployment on a [Kubernetes](https://kubernetes.io/) cluster using the [Helm](https://helm.sh/) package manager.

The chart deploys only TBMQ application components (broker nodes and integration executors). Infrastructure dependencies — PostgreSQL, Kafka, and Redis/Valkey — must be deployed separately using any method that fits your environment (operators, managed services, raw manifests, etc.).

## Prerequisites

- Kubernetes 1.23+
- Helm 3.10+
- External PostgreSQL instance
- External Kafka cluster
- External Redis-compatible cache (Redis, Valkey, Dragonfly, etc.)

## Installing the Chart

### Step 1: Add the TBMQ Helm Repository

```bash
helm repo add tbmq-helm-chart https://helm.thingsboard.io/tbmq
helm repo update
```

### Step 2: Retrieve and Modify Default Chart Values

```bash
helm show values tbmq-helm-chart/tbmq-cluster > values.yaml
```

Edit the `values.yaml` file to configure connection details for your external PostgreSQL, Kafka, and Redis/Valkey instances.

> **Warning:** Do not modify `installation.installDbSchema` directly in the `values.yaml`. This parameter is only required during 
the first installation to initialize the TBMQ database schema. Instead, pass it explicitly using `--set` in the `helm install` command.

### Step 3: Run the Installation Command

**Community Edition (CE):**

```bash
helm install my-tbmq-cluster tbmq-helm-chart/tbmq-cluster \
  -f values.yaml \
  --set installation.installDbSchema=true
```

**Professional Edition (PE):**

```bash
helm install my-tbmq-cluster tbmq-helm-chart/tbmq-cluster \
  -f values-pe.yaml \
  -f values.yaml \
  --set installation.installDbSchema=true
```

The `values-pe.yaml` overlay switches image repositories to the PE variants (`thingsboard/tbmq-pe-node` and `thingsboard/tbmq-pe-integration-executor`). Your `values.yaml` is applied on top to configure infrastructure connections and any other overrides.

> **Tip:** `my-tbmq-cluster` is the **Helm release name**. You can change it to any name of your choice.

## Updating Configuration

You can update your TBMQ deployment configuration — for example, scaling replicas or changing resource limits — 
by modifying `values.yaml` and applying the changes:

```bash
helm upgrade my-tbmq-cluster tbmq-helm-chart/tbmq-cluster -f values.yaml
```

Pods will automatically restart when ConfigMaps or Secrets that affect runtime behavior change (controlled by `enableChecksumAnnotations`). Logback configuration changes do not trigger restarts — TBMQ picks them up automatically via hot-reload.

## Upgrading

When moving to a new TBMQ chart release, a database schema migration may be required. To ensure consistency, TBMQ nodes should be temporarily scaled down before applying the upgrade.

### Backup (Recommended)

Back up your PostgreSQL database before proceeding with any upgrade. Follow the instructions provided by your PostgreSQL operator or cloud provider.

### Upgrading to 2.0.0

This is a **breaking change** release. All Bitnami subchart dependencies (PostgreSQL, Redis Cluster, Kafka) have been removed. Infrastructure must now be deployed externally.

**If you are upgrading from chart version 1.x:**

1. Deploy external PostgreSQL, Kafka, and Redis/Valkey instances (if not already in place).
2. Update your `values.yaml` to use the new top-level configuration keys (`postgresql:`, `kafka:`, `redis:`) instead of the old Bitnami subchart keys.
3. Scale down TBMQ nodes:

```bash
kubectl -n <namespace> scale statefulset/<release>-tbmq-node --replicas=0
```

4. Run the upgrade:

```bash
helm upgrade my-tbmq-cluster tbmq-helm-chart/tbmq-cluster \
  --version 2.0.0 \
  -f values.yaml \
  --set upgrade.upgradeDbSchema=true
```

### CE to PE Upgrade

To upgrade from Community Edition to Professional Edition on the same TBMQ version:

```bash
helm upgrade my-tbmq-cluster tbmq-helm-chart/tbmq-cluster \
  -f values-pe.yaml \
  -f values.yaml \
  --set upgrade.upgradeDbSchema=true \
  --set upgrade.fromVersion=ce
```

The `upgrade.fromVersion=ce` flag passes `-Dinstall.upgrade.from_version=ce` to the upgrade job, enabling the CE-to-PE data migration. Remove this flag for subsequent PE-to-PE upgrades.

### Troubleshooting

During the upgrade process, the chart creates a temporary pod to run the upgrade job, e.g., `my-tbmq-cluster-upgrade-3-r4cn6`.
If the upgrade fails, inspect the upgrade pod logs:

```bash
kubectl -n <namespace> logs -f <upgrade-pod-name>
```

> **Warning:** Upgrade pods have a short lifetime (ttlSecondsAfterFinished: 300), so they are automatically cleaned up 5 minutes after completion. Check the logs promptly.

## Configuration and Parameters

### Global Parameters

| **Parameter**                | **Description**                                                                                       | **Default Value**           |
|------------------------------|-------------------------------------------------------------------------------------------------------|-----------------------------|
| **Docker Authentication**    |                                                                                                       |                             |
| dockerAuth.registry          | Docker registry for TBMQ images.                                                                      | https://index.docker.io/v1/ |
| dockerAuth.username          | Docker username for pull secret.                                                                      | ""                          |
| dockerAuth.password          | Docker password for pull secret.                                                                      | ""                          |
| **Installation options**     |                                                                                                       |                             |
| installation.installDbSchema | Initializes the TBMQ PostgreSQL database schema. Required on first install.                           | false                       |
| installation.argocd          | Enables ArgoCD-specific Helm hook annotations.                                                        | false                       |
| **Upgrade options**          |                                                                                                       |                             |
| upgrade.upgradeDbSchema      | Runs database schema migration during `helm upgrade`. Ignored if not an upgrade.                      | false                       |
| upgrade.argocd               | Enables ArgoCD-specific Helm hook annotations for upgrade.                                            | false                       |
| upgrade.fromVersion          | Set to `"ce"` when upgrading from CE to PE. Passes `-Dinstall.upgrade.from_version` to the upgrade job. Leave empty for normal upgrades. | ""                          |

### TBMQ Parameters

| **Parameter**                               | **Description**                                                                                                                           | **Default Value**                       |
|---------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| **Image Configuration**                     |                                                                                                                                           |                                       |
| tbmq.image.repository                       | Docker image repository for TBMQ node. PE: `thingsboard/tbmq-pe-node`                                                                    | thingsboard/tbmq-node                 |
| tbmq.image.tag                              | Image tag/version.                                                                                                                        | 2.2.0                                 |
| tbmq.imagePullSecret                        | Kubernetes secret for pulling private images.                                                                                             | regcred                               |
| tbmq.imagePullPolicy                        | Image pull policy.                                                                                                                        | Always                                |
| **Scaling & Deployment**                    |                                                                                                                                           |                                       |
| tbmq.statefulSet.replicas                   | Number of TBMQ broker instances.                                                                                                          | 2                                     |
| tbmq.statefulSet.annotations                | Custom annotations on the StatefulSet resource.                                                                                           | { }                                   |
| **Ports**                                   |                                                                                                                                           |                                       |
| tbmq.ports                                  | HTTP (8083), HTTPS (443), MQTT (1883), MQTTS (8883), WS (8084), WSS (8085)                                                                |                                       |
| **Scheduling**                              |                                                                                                                                           |                                       |
| tbmq.nodeSelector                           | Node selector for pod scheduling.                                                                                                         | { }                                   |
| tbmq.affinity                               | Affinity rules for pod scheduling.                                                                                                        | { }                                   |
| **Configuration**                           |                                                                                                                                           |                                       |
| tbmq.customEnv                              | Custom environment variables. Override any conflicting variables from ConfigMaps.                                                          | { SECURITY_MQTT_BASIC_ENABLED: "true" } |
| tbmq.existingConfigMap                      | Existing ConfigMap with both `conf` and `logback` keys. Highest priority — ignores the two below.                                         | ""                                    |
| tbmq.existingJavaOptsConfigMap              | Existing ConfigMap with `conf` key (Java options).                                                                                        | ""                                    |
| tbmq.existingLogbackConfigMap               | Existing ConfigMap with `logback` key (logging configuration).                                                                            | ""                                    |
| tbmq.enableChecksumAnnotations              | Auto-restart pods when ConfigMaps/Secrets change (except logback — hot-reloaded).                                                         | true                                  |
| tbmq.annotations                            | Custom annotations on TBMQ pods.                                                                                                          | { }                                   |
| **Health Checks**                           |                                                                                                                                           |                                       |
| tbmq.readinessProbe                         | TCP check on port 1883. Initial delay: 30s, period: 20s.                                                                                  |                                       |
| tbmq.livenessProbe                          | TCP check on port 1883. Initial delay: 60s, period: 10s.                                                                                  |                                       |
| **Security & Resources**                    |                                                                                                                                           |                                       |
| tbmq.securityContext                        | runAsUser: 799, runAsNonRoot: true, fsGroup: 799                                                                                          |                                       |
| tbmq.resources                              | CPU/memory requests and limits.                                                                                                           | { }                                   |

### TBMQ Integration Executor Parameters

| **Parameter**                               | **Description**                                                                                                                           | **Default Value**                       |
|---------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| **Image Configuration**                     |                                                                                                                                           |                                       |
| tbmq-ie.image.repository                    | Docker image repository for TBMQ-IE. PE: `thingsboard/tbmq-pe-integration-executor`                                                      | thingsboard/tbmq-integration-executor |
| tbmq-ie.image.tag                           | Image tag/version.                                                                                                                        | 2.2.0                                 |
| tbmq-ie.imagePullSecret                     | Kubernetes secret for pulling private images.                                                                                             | regcred                               |
| tbmq-ie.imagePullPolicy                     | Image pull policy.                                                                                                                        | Always                                |
| **Scaling & Deployment**                    |                                                                                                                                           |                                       |
| tbmq-ie.statefulSet.replicas                | Number of TBMQ-IE instances.                                                                                                              | 2                                     |
| tbmq-ie.statefulSet.annotations             | Custom annotations on the StatefulSet resource.                                                                                           | { }                                   |
| **Ports**                                   |                                                                                                                                           |                                       |
| tbmq-ie.ports                               | HTTP (8082)                                                                                                                               |                                       |
| **Scheduling**                              |                                                                                                                                           |                                       |
| tbmq-ie.nodeSelector                        | Node selector for pod scheduling.                                                                                                         | { }                                   |
| tbmq-ie.affinity                            | Affinity rules for pod scheduling.                                                                                                        | { }                                   |
| **Configuration**                           |                                                                                                                                           |                                       |
| tbmq-ie.customEnv                           | Custom environment variables.                                                                                                             | { }                                   |
| tbmq-ie.existingConfigMap                   | Existing ConfigMap with both `conf` and `logback` keys.                                                                                   | ""                                    |
| tbmq-ie.existingJavaOptsConfigMap           | Existing ConfigMap with `conf` key (Java options).                                                                                        | ""                                    |
| tbmq-ie.existingLogbackConfigMap            | Existing ConfigMap with `logback` key (logging configuration).                                                                            | ""                                    |
| tbmq-ie.enableChecksumAnnotations           | Auto-restart pods when ConfigMaps/Secrets change (except logback — hot-reloaded).                                                         | true                                  |
| tbmq-ie.annotations                         | Custom annotations on TBMQ-IE pods.                                                                                                       | { }                                   |
| **Health Checks**                           |                                                                                                                                           |                                       |
| tbmq-ie.readinessProbe                      | TCP check on port http. Period: 20s.                                                                                                      |                                       |
| tbmq-ie.livenessProbe                       | TCP check on port http. Initial delay: 120s, period: 20s.                                                                                 |                                       |
| **Security & Resources**                    |                                                                                                                                           |                                       |
| tbmq-ie.securityContext                     | runAsUser: 799, runAsNonRoot: true, fsGroup: 799                                                                                          |                                       |
| tbmq-ie.resources                           | CPU/memory requests and limits.                                                                                                           | { }                                   |

## Infrastructure Configuration

TBMQ requires three external services: PostgreSQL, Kafka, and a Redis-compatible cache. Deploy these using any method that fits your environment, then configure the connection details below.

For a step-by-step example using Minikube with CrunchyData PGO, Strimzi Kafka, and Valkey, see the [Minikube Deployment Guide](docs/minikube/README.md).

### PostgreSQL

| **Parameter**                     | **Description**                                                              | **Default Value**           |
|-----------------------------------|------------------------------------------------------------------------------|-----------------------------|
| postgresql.host                   | PostgreSQL server host.                                                      | ""                          |
| postgresql.port                   | PostgreSQL server port.                                                      | 5432                        |
| postgresql.database               | Database name for TBMQ.                                                      | "thingsboard_mqtt_broker"   |
| postgresql.username               | PostgreSQL username.                                                         | "postgres"                  |
| postgresql.password               | PostgreSQL password (ignored if `existingSecret` is set).                    | ""                          |
| postgresql.existingSecret         | Name of an existing Secret containing the password.                          | ""                          |
| postgresql.existingSecretPasswordKey | Key within the Secret that holds the password.                            | ""                          |

**Example:**

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

| **Parameter**              | **Description**                                            | **Default Value** |
|----------------------------|------------------------------------------------------------|-------------------|
| kafka.bootstrapServers     | Comma-separated list of `host:port` bootstrap servers.     | ""                |

**Example:**

```yaml
kafka:
  bootstrapServers: "kafka-0:9092,kafka-1:9092,kafka-2:9092"
```

### Redis / Valkey / Cache

TBMQ uses the Redis protocol for caching. Any Redis-compatible backend (Redis, Valkey, Dragonfly, etc.) can be used.

| **Parameter**                  | **Description**                                                              | **Default Value** |
|--------------------------------|------------------------------------------------------------------------------|-------------------|
| redis.connectionType           | Connection type: `"standalone"` or `"cluster"`.                              | "cluster"         |
| redis.host                     | Host for standalone mode.                                                    | ""                |
| redis.port                     | Port for standalone mode.                                                    | 6379              |
| redis.nodes                    | Comma-separated `host:port` pairs for cluster mode.                          | ""                |
| redis.usePassword              | Whether the server requires password authentication.                         | true              |
| redis.password                 | Password (ignored if `existingSecret` is set).                               | ""                |
| redis.existingSecret           | Name of an existing Secret containing the password.                          | ""                |
| redis.existingSecretPasswordKey | Key within the Secret that holds the password.                              | ""                |

**Cluster mode example:**

```yaml
redis:
  connectionType: "cluster"
  nodes: "redis-0:6379,redis-1:6379,redis-2:6379,redis-3:6379,redis-4:6379,redis-5:6379"
  existingSecret: "my-redis-secret"
  existingSecretPasswordKey: "redis-password"
```

**Standalone mode example:**

```yaml
redis:
  connectionType: "standalone"
  host: "valkey.example.com"
  port: 6379
  usePassword: false
```

### Load Balancer Configuration

The chart creates Kubernetes Ingress and Service resources for HTTP and MQTT traffic. It does **not** deploy a load balancer or ingress controller — these must exist in your cluster.

Supported types: `nginx`, `aws`, `azure`, `gcp`.

| **Parameter**                                           | **Description**                                                                               | **Default Value**            |
|---------------------------------------------------------|-----------------------------------------------------------------------------------------------|------------------------------|
| loadbalancer.type                                       | Load balancer type: `"nginx"`, `"aws"`, `"azure"`, `"gcp"`.                                   | "nginx"                      |
| loadbalancer.http.enabled                               | Enable HTTP Ingress (L7).                                                                     | true                         |
| loadbalancer.http.annotations                           | Extra annotations for the HTTP Ingress. Merged with provider defaults.                        | { }                          |
| loadbalancer.http.ssl.enabled                           | Enable HTTPS termination at the load balancer.                                                | false                        |
| loadbalancer.http.ssl.certificateRef                    | SSL certificate reference (ACM ARN for AWS, appgw-ssl-certificate for Azure, ManagedCertificate name for GCP). | ""                           |
| loadbalancer.http.ssl.domains                           | List of domains for HTTPS (required for GCP ManagedCertificate).                              | ["www.example.com"]          |
| loadbalancer.http.ssl.staticIP                          | Static IP for GCP HTTP(S) LB. Ignored for other types.                                       | "tbmq-http-lb-address"       |
| loadbalancer.mqtt.enabled                               | Enable MQTT LoadBalancer service (L4).                                                        | true                         |
| loadbalancer.mqtt.annotations                           | Extra annotations for the MQTT Service. Merged with provider defaults.                        | { }                          |
| loadbalancer.mqtt.mutualTls.enabled                     | Enable mTLS at the TBMQ application level. Requires certificate + private key.                | false                        |
| loadbalancer.mqtt.mutualTls.configMapName               | ConfigMap with `server.pem` and `mqttserver_key.pem` keys.                                    | "tbmq-node-mqtts-config"    |
| loadbalancer.mqtt.mutualTls.privateKeyPasswordSecret    | Secret containing the private key password (optional).                                        | ""                           |
| loadbalancer.mqtt.mutualTls.privateKeyPasswordSecretKey | Key in the Secret with the private key password.                                              | "key_password"               |
| loadbalancer.mqtt.tlsTermination.enabled                | Enable one-way TLS termination at L4 (AWS NLB only). Ignored if mTLS is enabled.             | false                        |
| loadbalancer.mqtt.tlsTermination.certificateRef         | ACM certificate ARN for NLB TLS termination (AWS only).                                      | ""                           |

### Configuring Mutual TLS (mTLS) for MQTT

To enable mTLS, create a ConfigMap with your certificate and private key:

```bash
kubectl create configmap tbmq-node-mqtts-config \
    --from-file=server.pem=/path/to/server.pem \
    --from-file=mqttserver_key.pem=/path/to/mqttserver_key.pem \
    -o yaml --dry-run=client | kubectl apply -f -
```

If your private key requires a password, store it in a Secret:

```bash
kubectl create secret generic mqtt-tls-secret \
    --from-literal=key_password="YOUR_KEY_PASSWORD" \
    -o yaml --dry-run=client | kubectl apply -f -
```

Then configure in your `values.yaml`:

```yaml
loadbalancer:
  mqtt:
    enabled: true
    mutualTls:
      enabled: true
      configMapName: "tbmq-node-mqtts-config"
      privateKeyPasswordSecret: "mqtt-tls-secret"
      privateKeyPasswordSecretKey: "key_password"
```

## Professional Edition (PE)

The same chart supports both Community Edition (CE) and Professional Edition (PE). The only difference is the Docker image repositories.

**PE images:**
- `thingsboard/tbmq-pe-node` (instead of `thingsboard/tbmq-node`)
- `thingsboard/tbmq-pe-integration-executor` (instead of `thingsboard/tbmq-integration-executor`)

Use the provided `values-pe.yaml` overlay to switch to PE images:

```bash
# PE install
helm install my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f values-pe.yaml -f values.yaml \
  --set installation.installDbSchema=true

# PE upgrade
helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f values-pe.yaml -f values.yaml \
  --set upgrade.upgradeDbSchema=true

# CE to PE migration (same version)
helm upgrade my-tbmq tbmq-helm-chart/tbmq-cluster \
  -f values-pe.yaml -f values.yaml \
  --set upgrade.upgradeDbSchema=true \
  --set upgrade.fromVersion=ce
```

## Uninstalling

```bash
helm delete my-tbmq-cluster -n <namespace>
```

> **Warning:** `helm delete` removes the logical resources. To completely remove persistent data, delete the PVCs:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=my-tbmq-cluster -n <namespace>
```
