# Helm Chart for TBMQ Cluster

TBMQ represents an open-source MQTT message broker with the capacity to handle 4M+ concurrent client connections, 
supporting a minimum of 3M messages per second throughput per single cluster node with low latency delivery. 
In the cluster mode, its capabilities are further enhanced, enabling it to support more than 100M concurrently connected clients.

**Documentation & Resources:**

 - 🔗 TBMQ [Documentation](https://thingsboard.io/products/mqtt-broker/)
 - 💻 TBMQ GitHub [Repository](https://github.com/thingsboard/tbmq)
 - 💻 ThinsBoard Charts GitHub [Repository](https://github.com/thingsboard/helm-charts)

> **📜 Trademarks:** This software listing is packaged by TBMQ Team. 
The respective trademarks mentioned in the offering are owned by the respective companies, and use of them does not imply any affiliation or endorsement.

## Introduction

This chart bootstraps a TBMQ deployment on a [Kubernetes](https://kubernetes.io/) cluster using the [Helm](https://helm.sh/) package manager.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- PV provisioner support in the underlying infrastructure

## Installing the Chart

To install TBMQ using this Helm chart, follow these steps:

### Step 1: Add the TBMQ Helm Repository

Before installing the chart, add the TBMQ Helm repository to your local Helm client:

```bash
helm repo add tbmq-helm-chart https://helm.thingsboard.io/tbmq
helm repo update
```

### Step 2: Retrieve and Modify Default Chart Values

To customize your TBMQ deployment, retrieve the default `values.yaml` file from the Helm repository and modify it according to your requirements:

```bash
helm show values tbmq-helm-chart/tbmq-cluster > values.yaml
```

Edit the `values.yaml` file to configure TBMQ specific sections along with sub-charts included as a dependencies.
E.g., `redis-cluster`, `kafka`, `postgresql`.

> ⚠️ **Warning:** Do not modify `installation.installDbSchema` directly in the `values.yaml`. This parameter is only required during 
the first installation to initialize the TBMQ database schema. Instead, we will pass it explicitly using `--set` option in the `helm install` command.

### Step 3: Run the Installation Command

After modifying the `values.yaml` file, install TBMQ using the following command:

```bash
helm install my-tbmq-cluster tbmq-helm-chart/tbmq-cluster -f values.yaml --set installation.installDbSchema=true
```

> 💡 **Tip:** `my-tbmq-cluster` is the **Helm release name**. You can change it to any name of your choice, which will be used to reference this deployment in future Helm commands.

## Updating configuration

You can update your TBMQ deployment configuration — for example, scaling replicas or changing resource limits — 
by modifying `values.yaml` and applying the changes using the `helm upgrade` command:

```bash
helm upgrade my-tbmq-cluster tbmq-helm-chart/tbmq-cluster -f values.yaml
```

## Upgrading

When moving to a new TBMQ chart release, a database schema migration is required. To ensure consistency, TBMQ nodes must be temporarily scaled down before applying the upgrade.

### Backup and restore (Optional)

While backing up your PostgreSQL database is highly recommended, it is optional before proceeding with the upgrade.

 - If you are using the built-in Bitnami PostgreSQL, follow the official Bitnami backup and restore [documentation](https://artifacthub.io/packages/helm/bitnami/postgresql#backup-and-restore).
 - If you are using an external PostgreSQL (for example, AWS RDS, Google Cloud SQL, or Azure Database), please follow the instructions provided by your cloud provider.

### Upgrading to 1.1.0

This chart upgrade includes a TBMQ application version bump from 2.1.0 to 2.2.0. 
Before proceeding, please review the TBMQ [release notes](https://thingsboard.io/docs/mqtt-broker/releases/) for detailed information on the latest changes.

> ⚠️ **Warning:**: Starting with this release, TBMQ Helm charts use Bitnami Legacy images (bitnamilegacy/*) for PostgreSQL, Redis, and Kafka due to upcoming [Bitnami registry changes](https://github.com/bitnami/charts/issues/35164) on August 28th 2025.

#### Step 1: Update the repo and ensure version 1.1.0 is available

```bash
helm repo update
helm search repo tbmq-helm-chart/tbmq-cluster --versions | grep 1.1.0
```

Expected output:

```bash
tbmq-helm-chart/tbmq-cluster	1.1.0        	2.2.0         	Helm chart for TBMQ cluster.    
```

This confirms that chart version `1.1.0` is available in your local Helm repository cache.

#### Step 2: Scale down TBMQ node replicas

Before applying the `helm upgrade` command,
please scale down the running TBMQ nodes to 0 replicas
to avoid running mixed versions during the database schema upgrade:

```bash
kubectl -n <namespace_name> scale statefulset/my-tbmq-cluster-tbmq-node --replicas=0
```

This ensures that no TBMQ nodes are connected to PostgreSQL while the database schema upgrade runs.

#### Step 3: Run the upgrade:

```bash
helm upgrade my-tbmq-cluster tbmq-helm-chart/tbmq-cluster \
  --version 1.1.0 \
  -f values.yaml \
  --set upgrade.upgradeDbSchema=true
```

Example output:

```bash
Release "my-tbmq-cluster" has been upgraded. Happy Helming!
NAME: my-tbmq-cluster
LAST DEPLOYED: Thu Aug 21 15:04:28 2025
NAMESPACE: tbmq
STATUS: deployed
REVISION: 2
TEST SUITE: None
NOTES:
TBMQ Cluster my-tbmq-cluster will be deployed in few minutes.
Info:
    Namespace: tbmq
```

### Troubleshooting

During the upgrade process, the chart creates a temporary pod to run the upgrade job, e.g., `my-tbmq-cluster-upgrade-3-r4cn6`.
If the upgrade fails, e.g., due to CrashLoopBackOff or a timeout while waiting for hook completion, you can inspect the upgrade pod logs to understand what went wrong:

```bash
kubectl -n <namespace_name> logs -f my-tbmq-cluster-upgrade-3-r4cn6
```

> ⚠️ **Warning:**: Upgrade pods have a short lifetime (ttlSecondsAfterFinished: 300), so they are automatically cleaned up 5 minutes after completion. Make sure to check the logs promptly.

## Configuration and Parameters

This section describes the configurable parameters of the TBMQ Helm chart. The `values.yaml` file includes settings for TBMQ itself and its required dependencies.

### Global Parameters

These parameters apply to the overall chart, such as image pull credentials and installation behavior.

- **dockerAuth** – Configures authentication for pulling images from a private Docker registry. 
By default, TBMQ images are publicly available, but authentication settings can be provided if using a private registry.
- **installation** – Controls the installation options, including database schema initialization and [ArgoCD](https://argoproj.github.io/cd/) support.
- **upgrade** – Controls the upgrade options, including database schema upgrade and [ArgoCD](https://argoproj.github.io/cd/) support.

Please refer to the table below for parameter descriptions and default values.

| **Parameter**                | **Description**                                                                                                                                                                                                                                                                                                                                                                                                      | **Default Value**           |
|------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|
| **Docker Authentication**    |                                                                                                                                                                                                                                                                                                                                                                                                                      |                             |
| dockerAuth.registry          | Docker registry for TBMQ images.                                                                                                                                                                                                                                                                                                                                                                                     | https://index.docker.io/v1/ |
| dockerAuth.username          | Docker username on which pull secret will be created.                                                                                                                                                                                                                                                                                                                                                                | ""                          |
| dockerAuth.password          | Docker user password on which pull secret will be created.                                                                                                                                                                                                                                                                                                                                                           | ""                          |
| **Installation options**     |                                                                                                                                                                                                                                                                                                                                                                                                                      |                             |
| installation.installDbSchema | This field is responsible for the installation process of TBMQ PostgreSQL database schema.                                                                                                                                                                                                                                                                                                                           | false                       |
| installation.argocd          | Enables ArgoCD-specific Helm annotations for managing TBMQ deployments with ArgoCD. When set to true, the chart applies the following ArgoCD hooks: <pre><br/> argocd.argoproj.io/hook: Sync  – Ensures that the Helm release is treated as a sync hook. <br/> argocd.argoproj.io/hook-delete-policy: HookSucceeded – Automatically removes the hook resources once the sync operation completes successfully.</pre> | false                       |
| **Upgrade options**          |                                                                                                                                                                                                                                                                                                                                                                                                                      |                             |
| upgrade.upgradeDbSchema      | This field is responsible for the upgrade process of TBMQ PostgreSQL database schema. It will be ignored if the Helm release is not in the "upgrade" state.                                                                                                                                                                                                                                                          | false                       |
| upgrade.argocd               | Enables ArgoCD-specific Helm annotations for managing TBMQ deployments with ArgoCD. When set to true, the chart applies the following ArgoCD hooks: <pre><br/> argocd.argoproj.io/hook: PreSync  – Ensures that the Helm release is treated as a pre-sync hook. Executed before the main sync phase begins.                                                                                                          | false                       |

## TBMQ-Specific Parameters

This section describes the configuration options for the **TBMQ** and its **Integration Executor** component.

### TBMQ parameters

| **Parameter**                               | **Description**                                                                                                                                                                                                                                                | **Default Value**                       |
|---------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------|
| **Image Configuration**                     |                                                                                                                                                                                                                                                                |                                         |
| tbmq.image.repository                       | Docker image repository for TBMQ node.                                                                                                                                                                                                                         | thingsboard/tbmq-node                   |
| tbmq.image.tag                              | Image tag/version.                                                                                                                                                                                                                                             | 2.2.0                                   |
| tbmq.imagePullSecret                        | Kubernetes secret for pulling private images.                                                                                                                                                                                                                  | regcred                                 |
| tbmq.imagePullPolicy                        | Image pull policy.                                                                                                                                                                                                                                             | Always                                  |
| **Scaling & Deployment**                    |                                                                                                                                                                                                                                                                |                                         |
| tbmq.statefulSet.replicas                   | Number of TBMQ broker instances.                                                                                                                                                                                                                               | 2                                       |
| tbmq.statefulSet.annotations                | Custom annotations applied to the StatefulSet resource (metadata.annotations). These are useful for CI/CD tools, Helm diff, audit tracking, etc.                                                                                                               | { }                                     |
| **Ports configuration**                     |                                                                                                                                                                                                                                                                |                                         |
| tbmq.ports.http                             | HTTP API Port                                                                                                                                                                                                                                                  | 8083                                    |
| tbmq.ports.https                            | HTTPS API Port                                                                                                                                                                                                                                                 | 443`                                    |
| tbmq.ports.mqtt                             | MQTT Broker Port                                                                                                                                                                                                                                               | 1883                                    |
| tbmq.ports.mqtts                            | MQTT Secure Port (TLS)                                                                                                                                                                                                                                         | 8883                                    |
| tbmq.ports.mqtt-ws                          | MQTT over WebSockets Port                                                                                                                                                                                                                                      | 8084                                    |
| tbmq.ports.mqtt-wss                         | MQTT over Secure WebSockets Port (TLS)                                                                                                                                                                                                                         | 8085                                    |
| **Pods Scheduling, Restart options**        |                                                                                                                                                                                                                                                                |                                         |
| tbmq.nodeSelector                           | Node selector for choosing nodes for scheduling pods. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ for more details.                                                                                                           | { }                                     |
| tbmq.affinity                               | Affinity for choosing nodes for scheduling pods. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ for more details.                                                                                                                | { }                                     |
| tbmq.enableChecksumAnnotations              | Controls whether Helm automatically restarts TBMQ pods when ConfigMaps or Secrets change.                                                                                                                                                                      | true                                    |
| tbmq.annotations                            | Custom annotations applied to the TBMQ pods (spec.template.metadata.annotations). These are commonly used for service discovery (e.g., Prometheus scraping), config checksum triggers, or logging agents.                                                      | true                                    |
| tbmq.restartPolicy                          | Defines the restart policy for TBMQ pods.                                                                                                                                                                                                                      |                                         |
| **Environment, JVM and Logging Parameters** |                                                                                                                                                                                                                                                                |                                         |
| tbmq.customEnv                              | Custom environment variables that are always applied, regardless of configuration source. These variables will be appended to the container environment and will override any conflicting variables set in `existingConfigMap` or `existingJavaOptsConfigMap`. | { SECURITY_MQTT_BASIC_ENABLED: "true" } |
| tbmq.existingConfigMap                      | Name of an existing ConfigMap that will override TBMQ Java and Logback configurations. If set, this ConfigMap should contain BOTH Java options (`conf` key) and Logback settings (`logback` key).                                                              | ""                                      |
| tbmq.existingJavaOptsConfigMap              | Name of an existing TBMQ Java options config map. This ConfigMap should contain a key named `conf` with Java options.                                                                                                                                          | ""                                      |
| tbmq.existingLogbackConfigMap               | Name of an existing TBMQ logback config map. This ConfigMap should contain a key named `logback` with the logging configuration.                                                                                                                               | ""                                      |
| **Health Checks**                           |                                                                                                                                                                                                                                                                |                                         |
| tbmq.readinessProbe.tcpSocket.port          | Port checked to determine readiness.                                                                                                                                                                                                                           | 1883                                    |
| tbmq.readinessProbe.timeoutSeconds          | Maximum time to wait before considering the check failed.                                                                                                                                                                                                      | 10s                                     |
| tbmq.readinessProbe.initialDelaySeconds     | Delay before the first readiness probe.                                                                                                                                                                                                                        | 30s                                     |
| tbmq.readinessProbe.periodSeconds           | Interval between probe executions.                                                                                                                                                                                                                             | 20s                                     |
| tbmq.readinessProbe.successThreshold        | Minimum number of successes before marking pod as "ready".                                                                                                                                                                                                     | 1                                       |
| tbmq.readinessProbe.failureThreshold        | Number of failures before the pod is removed from service endpoints.                                                                                                                                                                                           | 5                                       |
| tbmq.livenessProbe.tcpSocket.port           | Port checked to determine liveness.                                                                                                                                                                                                                            | 1883                                    |
| tbmq.livenessProbe.timeoutSeconds           | Maximum time to wait before considering the check failed.                                                                                                                                                                                                      | 10s                                     |
| tbmq.livenessProbe.initialDelaySeconds      | Delay before the first liveness probe.                                                                                                                                                                                                                         | 60s                                     |
| tbmq.livenessProbe.periodSeconds            | Interval between probe executions.                                                                                                                                                                                                                             | 10s                                     |
| tbmq.livenessProbe.successThreshold         | Minimum number of successes before marking pod as "alive".                                                                                                                                                                                                     | 1                                       |
| tbmq.livenessProbe.failureThreshold         | Number of consecutive failures before restarting the pod.                                                                                                                                                                                                      | 10                                      |
| **Security Context**                        |                                                                                                                                                                                                                                                                |                                         |
| tbmq.securityContext.runAsUser              | User ID to run the container.                                                                                                                                                                                                                                  | 799                                     |
| tbmq.securityContext.runAsNonRoot           | Enforces non-root execution.                                                                                                                                                                                                                                   | true                                    |
| tbmq.securityContext.fsGroup                | File system group ID for permissions.                                                                                                                                                                                                                          | 799                                     |
| **Resources allocation**                    |                                                                                                                                                                                                                                                                |                                         |
| tbmq.resources                              | Defines CPU/memory requests & limits. See https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#pod-level-resource-specification for more details.                                                                                    | { }                                     |

### TBMQ Integration Executor Parameters

| **Parameter**                               | **Description**                                                                                                                                                                                                                                                | **Default Value**                     |
|---------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------|
| **Image Configuration**                     |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.image.repository                    | Docker image repository for TBMQ-IE node.                                                                                                                                                                                                                      | thingsboard/tbmq-integration-executor |
| tbmq-ie.image.tag                           | Image tag/version.                                                                                                                                                                                                                                             | 2.2.0                                 |
| tbmq-ie.imagePullSecret                     | Kubernetes secret for pulling private images.                                                                                                                                                                                                                  | regcred                               |
| tbmq-ie.imagePullPolicy                     | Image pull policy.                                                                                                                                                                                                                                             | Always                                |
| **Scaling & Deployment**                    |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.statefulSet.replicas                | Number of TBMQ-IE instances.                                                                                                                                                                                                                                   | 2                                     |
| tbmq-ie.statefulSet.annotations             | Custom annotations applied to the StatefulSet resource (metadata.annotations). These are useful for CI/CD tools, Helm diff, audit tracking, etc.                                                                                                               | { }                                   |
| **Ports configuration**                     |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.ports.http                          | HTTP API Port                                                                                                                                                                                                                                                  | 8082                                  |
| **Pods Scheduling, Restart options**        |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.nodeSelector                        | Node selector for choosing nodes for scheduling pods. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ for more details.                                                                                                           | { }                                   |
| tbmq-ie.affinity                            | Affinity for choosing nodes for scheduling pods. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ for more details.                                                                                                                | { }                                   |                                                                                                                                                                                                                                                                                     |
| tbmq-ie.enableChecksumAnnotations           | Controls whether Helm automatically restarts TBMQ IE pods when ConfigMaps or Secrets change.                                                                                                                                                                   | true                                  |                                                                                                                                                                                                                                                                                     |
| tbmq-ie.annotations                         | Custom annotations applied to the TBMQ pods (spec.template.metadata.annotations). These are commonly used for service discovery (e.g., Prometheus scraping), config checksum triggers, or logging agents.                                                      | true                                  |                                                                                                                                                                                                                                                                                     |
| tbmq-ie.restartPolicy                       | Defines the restart policy for TBMQ IE pods.                                                                                                                                                                                                                   |                                       |                                                                                                                                                                                                                                                                                     |
| **Environment, JVM and Logging Parameters** |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.customEnv                           | Custom environment variables that are always applied, regardless of configuration source. These variables will be appended to the container environment and will override any conflicting variables set in `existingConfigMap` or `existingJavaOptsConfigMap`. | { }                                   |
| tbmq-ie.existingConfigMap                   | Name of an existing ConfigMap that will override TBMQ-IE Java and Logback configurations. If set, this ConfigMap should contain BOTH Java options (`conf` key) and Logback settings (`logback` key).                                                           | ""                                    |
| tbmq-ie.existingJavaOptsConfigMap           | Name of an existing TBMQ-IE Java options config map. This ConfigMap should contain a key named `conf` with Java options.                                                                                                                                       | ""                                    |
| tbmq-ie.existingLogbackConfigMap            | Name of an existing TBMQ-IE logback config map. This ConfigMap should contain a key named `logback` with the logging configuration.                                                                                                                            | ""                                    |
| **Health Checks**                           |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.readinessProbe.tcpSocket.port       | Port checked to determine readiness.                                                                                                                                                                                                                           | http                                  |
| tbmq-ie.readinessProbe.periodSeconds        | Interval between probe executions.                                                                                                                                                                                                                             | 20s                                   |
| tbmq-ie.livenessProbe.tcpSocket.port        | Port checked to determine liveness.                                                                                                                                                                                                                            | http                                  |
| tbmq-ie.livenessProbe.initialDelaySeconds   | Delay before the first liveness probe.                                                                                                                                                                                                                         | 120s                                  |
| tbmq-ie.livenessProbe.periodSeconds         | Interval between probe executions.                                                                                                                                                                                                                             | 20s                                   |
| **Security Context**                        |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.securityContext.runAsUser           | User ID to run the container.                                                                                                                                                                                                                                  | 799                                   |
| tbmq-ie.securityContext.runAsNonRoot        | Enforces non-root execution.                                                                                                                                                                                                                                   | true                                  |
| tbmq-ie.securityContext.fsGroup             | File system group ID for permissions.                                                                                                                                                                                                                          | 799                                   |
| **Resources allocation**                    |                                                                                                                                                                                                                                                                |                                       |
| tbmq-ie.resources                           | Defines CPU/memory requests & limits. See https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#pod-level-resource-specification for more details.                                                                                    | { }                                   |

## Infrastructure Services for TBMQ

TBMQ relies on several external services to handle persistence, message routing, and caching. 
This Helm chart provides built-in support for deploying these dependencies using [Bitnami](https://bitnami.com/) Helm charts.

For the first release, only external PostgreSQL is supported, allowing TBMQ to connect to an existing database instance instead of deploying PostgreSQL using Bitnami within the cluster.
Future releases will extend support for external Kafka and Redis, enabling users to connect to managed or self-hosted instances of these services.

### Configuring Bitnami Sub-Charts

This Helm chart exposes only the settings required for deployment and the ones considered essential for configuring
a high-availability (HA) setup based on current use cases and our practical experience.
These parameters are included by default in `values.yaml` to simplify the update process for K8S administrators.

You can find the exposed settings in the corresponding sections of `values.yaml` such as `postgresql`, `kafka` and `redis-cluster`.
For advanced customization, you can override any parameter of the Bitnami sub-charts by specifying chart supported keys under the respective section. 
These values will be passed directly to the underlying Bitnami chart.

### Bitnami Kafka 

TBMQ uses Kafka as a core component for handling message persistence and delivery, particularly for scalability and fault tolerance.

This Helm chart integrates Bitnami Kafka, which provides a Kubernetes-native deployment with built-in HA (high availability) support.
By default, this chart deploys a 3-node Kafka cluster, ensuring fault tolerance and efficient message distribution.
Users can fine-tune Kafka's configuration to align with their persistence and durability requirements.

Please refer to the table below to review exposed parameters, their descriptions, and default values.

| **Parameter**                                       | **Description**                                                                                                                                                                                                          | **Default Value**                                                                                                                                                                                     |
|-----------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Kafka Deployment Settings**                       |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.nameOverride                                  | Override default Kafka cluster name.                                                                                                                                                                                     | "kafka"                                                                                                                                                                                               |
| kafka.image.repository                              | Docker image repository for Kafka. Defaults to the Bitnami Legacy registry to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164                   | bitnamilegacy/kafka                                                                                                                                                                                   |
| kafka.heapOpts                                      | Java heap size configuration for Kafka nodes.                                                                                                                                                                            | -Xmx1024m -Xms1024m                                                                                                                                                                                   |
| kafka.controller.replicaCount                       | Number of Kafka controller nodes.                                                                                                                                                                                        | 3                                                                                                                                                                                                     |
| kafka.controller.resources                          | Defines CPU/memory requests & limits for Kafka pods.                                                                                                                                                                     | 3                                                                                                                                                                                                     |
| **Kafka Configuration Parameters**                  |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.extraConfig                                   | Additional Kafka configuration appended to the default settings.                                                                                                                                                         | <pre>auto.create.topics.enable=false<br/>default.replication.factor=2<br/>offsets.topic.replication.factor=3<br/>transaction.state.log.replication.factor=3<br/>transaction.state.log.min.isr=2</pre> |
| **Kafka Listeners**                                 |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| listeners.client.protocol                           | Security protocol for the Kafka client listener.                                                                                                                                                                         | PLAINTEXT                                                                                                                                                                                             |
| listeners.controller.protocol                       | Security protocol for the Kafka controller listener.                                                                                                                                                                     | PLAINTEXT                                                                                                                                                                                             |
| listeners.interbroker.protocol                      | Security protocol for the Kafka inter-broker listener.                                                                                                                                                                   | PLAINTEXT                                                                                                                                                                                             |
| listeners.external.protocol                         | Security protocol for the Kafka external listener.                                                                                                                                                                       | PLAINTEXT                                                                                                                                                                                             |
| **Kafka High Availability & Pod Scheduling**        |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.controller.podAntiAffinityPreset              | Ensures Kafka brokers are scheduled on different nodes. Allowed values: soft or hard.                                                                                                                                    | soft                                                                                                                                                                                                  |
| kafka.controller.affinity                           | Custom node affinity rules for Kafka controllers.                                                                                                                                                                        | { }                                                                                                                                                                                                   |
| kafka.controller.nodeSelector                       | Inter-broker communication.                                                                                                                                                                                              | { }                                                                                                                                                                                                   |
| kafka.controller.nodeAffinityPreset.type            | Node affinity preset type. Allowed values: "soft" or "hard".                                                                                                                                                             | ""                                                                                                                                                                                                    |
| kafka.controller.nodeAffinityPreset.key             | Node label key for affinity. Ignored if `kafka.controller.affinity` is set.                                                                                                                                              | ""                                                                                                                                                                                                    |
| kafka.controller.nodeAffinityPreset.values          | Node label values to match. Ignored if `kafka.controller.affinity` is set.                                                                                                                                               | ""                                                                                                                                                                                                    |
| **Pod Disruption Budget (PDB)**                     |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.controller.pdb.create                         | Enables Pod Disruption Budget for Kafka. See https://kubernetes.io/docs/concepts/workloads/pods/disruptions/ for more details.                                                                                           | false                                                                                                                                                                                                 |
| kafka.controller.pdb.maxUnavailable                 | Max number of pods that can be unavailable after the eviction. You can specify an integer or a percentage by setting the value to a string representation of a percentage (e.g. "50%"). It will be disabled if set to 0. | 1                                                                                                                                                                                                     |
| **Kafka Storage Configuration**                     |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.controller.persistence.existingClaim          | Use an existing Persistent Volume Claim.                                                                                                                                                                                 | ""                                                                                                                                                                                                    |
| kafka.controller.persistence.storageClass           | Storage class for Persistent Volume Claims. If undefined (the default) or set to null, no storageClassName spec is set, choosing the default provisioner e.g., gp2 on AWS, standard on GKE).                             | ""                                                                                                                                                                                                    |
| kafka.controller.persistence.accessModes            | Persistent Volume Access Modes.                                                                                                                                                                                          | ReadWriteOnce                                                                                                                                                                                         |
| kafka.controller.persistence.size                   | Size of data volume.                                                                                                                                                                                                     | 8Gi                                                                                                                                                                                                   |
| **External Access**                                 |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.externalAccess.autoDiscovery.image.repository | Helper image repository for external access auto‑discovery. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164              | bitnamilegacy/kubectl                                                                                                                                                                                 |
| **Volume Permissions**                              |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.volumePermissions.image.repository            | Helper image repository for volume permissions. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164                          | bitnamilegacy/os-shell                                                                                                                                                                                |
| **Monitoring & Metrics**                            |                                                                                                                                                                                                                          |                                                                                                                                                                                                       |
| kafka.metrics.jmx.enabled                           | Enable JMX metrics for Prometheus monitoring.                                                                                                                                                                            | false                                                                                                                                                                                                 |
| kafka.metrics.jmx.image.repository                  | JMX exporter image repository for Prometheus metrics. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164                    | bitnamilegacy/jmx-exporter                                                                                                                                                                            |
| kafka.metrics.jmx.kafkaJmxPort                      | JMX exporter port for Kafka metrics.                                                                                                                                                                                     | 5555                                                                                                                                                                                                  |
| kafka.metrics.jmx.resources                         | Define resources for the JMX exporter.                                                                                                                                                                                   | { }                                                                                                                                                                                                   |

🔗 See official Bitnami Kafka Artifact Hub [page](https://artifacthub.io/packages/helm/bitnami/kafka/29.3.4) for more details.

### Bitnami Redis Cluster

TBMQ uses Redis Cluster as persistent message storage and caching mechanism with low-latency access.
This Helm chart integrates Bitnami Redis Cluster, providing a highly available (HA) and scalable deployment for distributed caching.

By default, this chart deploys a 6-node Redis Cluster:

 - 3 master nodes for write operations.
 - 3 replica nodes to ensure redundancy and data replication.

This setup guarantees fault tolerance, automatic failover, and scalability.

Please refer to the table below to review exposed parameters descriptions and their default values.

| **Parameter**                                                  | **Description**                                                                                                                                                                                                          | **Default Value**            |
|----------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------|
| **General Configuration**                                      |                                                                                                                                                                                                                          |                              |
| redis-cluster.nameOverride                                     | Override default Redis cluster name.                                                                                                                                                                                     | "redis"                      |
| redis-cluster.image.repository                                 | Docker image repository for Redis Cluster. Defaults to the Bitnami Legacy registry to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164           | bitnamilegacy/redis-cluster  |
| redis-cluster.password                                         | Redis password (ignored if existingSecret set). Defaults to a random 10-character alphanumeric string if not set and usePassword is true.                                                                                | "myredispassword"            |
| redis-cluster.existingSecret                                   | Name of existing secret object (for password authentication)                                                                                                                                                             | ""                           |
| redis-cluster.existingSecretPasswordKey                        | Name of key containing password to be retrieved from the existing secret                                                                                                                                                 | ""                           |
| **Pod Disruption Budget (PDB)**                                |                                                                                                                                                                                                                          |                              |
| redis-cluster.pdb.create                                       | Enables Pod Disruption Budget for Redis. See https://kubernetes.io/docs/tasks/run-application/configure-pdb/ for more details.                                                                                           | false                        |
| redis-cluster.pdb.maxUnavailable                               | Max number of pods that can be unavailable after the eviction. You can specify an integer or a percentage by setting the value to a string representation of a percentage (e.g. "50%"). It will be disabled if set to 0. | 1                            |
| **Redis StatefulSet Configuration**                            |                                                                                                                                                                                                                          |                              |
| redis-cluster.redis.useAOFPersistence                          | Enables Append-Only File (AOF) persistence mode. See https://redis.io/topics/persistence#append-only-file and https://redis.io/topics/cluster-tutorial#creating-and-using-a-redis-cluster for more details.              | "yes"                        |
| redis-cluster.redis.resources                                  | Defines CPU/memory requests & limits. (essential for production workloads)                                                                                                                                               | { }                          |
| redis-cluster.redis.podAntiAffinityPreset                      | Redis pod anti-affinity. Allowed values: soft or hard. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity for more details.                               | soft                         |
| redis-cluster.redis.nodeAffinityPreset.type                    | Node affinity preset type. Ignored if `redis.affinity` is set. Allowed values: "soft" or "hard".                                                                                                                         | ""                           |
| redis-cluster.redis.nodeAffinityPreset.key                     | Node label key for affinity. Ignored if `redis.affinity` is set.                                                                                                                                                         | ""                           |
| redis-cluster.redis.nodeAffinityPreset.values                  | Node label values to match. Ignored if `redis.affinity` is set.                                                                                                                                                          | []                           |
| redis-cluster.redis.nodeSelector                               | Assigns Redis pods to specific nodes. See https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ for more details.                                                                                     | { }                          |
| redis-cluster.redis.affinity                                   | Custom affinity rules for Redis pods. See https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity for more details.                                                                | { }                          |
| **Redis Storage Configuration**                                |                                                                                                                                                                                                                          |                              |
| redis-cluster.persistence.storageClass                         | Storage class for Persistent Volume Claims. If undefined (the default) or set to null, no storageClassName spec is set, choosing the default provisioner e.g., gp2 on AWS, standard on GKE).                             | ""                           |
| redis-cluster.persistence.accessModes                          | Persistent Volume Access Modes.                                                                                                                                                                                          | ReadWriteOnce                |
| redis-cluster.persistence.size                                 | Size of data volume.                                                                                                                                                                                                     | 8Gi                          |
| **Persistent Volume Retention Policy**                         |                                                                                                                                                                                                                          |                              |
| redis-cluster.persistentVolumeClaimRetentionPolicy.enabled     | Controls if and how PVCs are deleted during the lifecycle of a StatefulSet.                                                                                                                                              | false                        |
| redis-cluster.persistentVolumeClaimRetentionPolicy.whenScaled  | Volume retention behavior when the replica count of the StatefulSet is reduced.                                                                                                                                          | Retain                       |
| redis-cluster.persistentVolumeClaimRetentionPolicy.whenDeleted | Volume retention behavior that applies when the StatefulSet is deleted.                                                                                                                                                  | Retain                       |
| **Cluster Settings**                                           |                                                                                                                                                                                                                          |                              |
| redis-cluster.cluster.nodes                                    | Total Redis nodes (includes both masters and replicas). Hence, nodes = numberOfMasterNodes + numberOfMasterNodes * replicas. The number of master nodes should always be >= 3, otherwise cluster creation will fail.     | 6                            |
| redis-cluster.cluster.replicas                                 | Number of replicas for every master in the cluster. 1 means that we want a replica for every master created.                                                                                                             | 1                            |
| **Cluster Updates Settings**                                   |                                                                                                                                                                                                                          |                              |
| redis-cluster.cluster.update.addNodes                          | Boolean to specify if you want to add nodes after the upgrade. Setting this to true a hook will add nodes to the Redis cluster after the upgrade. `currentNumberOfNodes` and `currentNumberOfReplicas` is required.      | false                        |
| redis-cluster.cluster.update.currentNumberOfNodes              | Number of currently deployed Redis nodes.                                                                                                                                                                                | 6                            |
| redis-cluster.cluster.update.currentNumberOfReplicas           | Number of currently deployed Redis replicas.                                                                                                                                                                             | 1                            |
| redis-cluster.cluster.update.newExternalIPs                    | External IPs obtained from the services for the new nodes to add to the cluster.                                                                                                                                         | []                           |
| **Volume Permissions**                                         |                                                                                                                                                                                                                          |                              |
| redis-cluster.volumePermissions.image.repository               | Helper image repository for volume permissions. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164                          | bitnamilegacy/os-shell       |
| **Monitoring & Metrics**                                       |                                                                                                                                                                                                                          |                              |
| redis-cluster.metrics.enabled                                  | Enables Redis Prometheus Exporter for monitoring.                                                                                                                                                                        | false                        |
| redis-cluster.metrics.image.repository                         | Redis exporter image repository for Prometheus metrics. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164                  | bitnamilegacy/redis-exporter |
| redis-cluster.metrics.resources                                | Resource limits/requests for the exporter.                                                                                                                                                                               | { }                          |
| **Sysctl InitContainer**                                       |                                                                                                                                                                                                                          |                              |
| redis-cluster.sysctlImage.repository                           | Init image repository for sysctl tuning. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164                                 | bitnamilegacy/os-shell       |

🔗 See official Bitnami Redis Cluster Artifact Hub [page](https://artifacthub.io/packages/helm/bitnami/redis-cluster/10.3.0) for more details.

### Bitnami PostgreSQL

TBMQ uses a PostgreSQL database to store different entities such as users, user credentials, MQTT client credentials, statistics, WebSocket connections, WebSocket subscriptions, and others.

Please refer to the table below to review exposed parameters descriptions and their default values.

| **Parameter**                                 | **Description**                                                                                                                                                                                             | **Default Value**               |
|-----------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------|
| **General setting**                           |                                                                                                                                                                                                             |                                 |
| postgresql.enabled                            | Enables Bitnami PostgreSQL installation.                                                                                                                                                                    | true                            |
| postgresql.nameOverride                       | Override the name of the PostgreSQL deployment.                                                                                                                                                             | "postgresql"                    |
| postgresql.image.repository                   | Docker image repository for PostgreSQL. Defaults to the Bitnami Legacy registry to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164 | bitnamilegacy/postgresql        |
| **Authentication configuration**              |                                                                                                                                                                                                             |                                 |
| postgresql.auth.enablePostgresUser            | Assign a password to the "postgres" admin user. Otherwise, remote access will be blocked for this user.                                                                                                     | true                            |
| postgresql.auth.postgresPassword              | Password for the "postgres" admin user. Ignored if `auth.existingSecret` is provided.                                                                                                                       | ""                              |
| postgresql.auth.username                      | Username for PostgreSQL authentication.                                                                                                                                                                     | "postgres"                      |
| postgresql.auth.password                      | Password for PostgreSQL authentication (change for production).                                                                                                                                             | "postgres"                      |
| postgresql.auth.existingSecret                | Name of existing secret to use for PostgreSQL credentials.                                                                                                                                                  | ""                              |
| postgresql.auth.secretKeys.adminPasswordKey   | Name of key in existing secret to use for PostgreSQL credentials. Only used when `auth.existingSecret` is set.                                                                                              | postgres-password               |
| postgresql.auth.secretKeys.userPasswordKey    | Name of key in existing secret to use for PostgreSQL credentials. Only used when `auth.existingSecret` is set.                                                                                              | password                        |
| postgresql.auth.database                      | PostgreSQL database name for TBMQ.                                                                                                                                                                          | "thingsboard_mqtt_broker"       |
| **Primary Resources allocation**              |                                                                                                                                                                                                             |                                 |
| postgresql.primary.resources                  | Resource requests/limits for primary PostgreSQL service                                                                                                                                                     | { }                             |
| **Primary Pods Scheduling**                   |                                                                                                                                                                                                             |                                 |
| postgresql.primary.nodeSelector               | Node labels for PostgreSQL primary pods assignment                                                                                                                                                          | { }                             |
| **Primary Storage Configuration**             |                                                                                                                                                                                                             |                                 |
| postgresql.primary.persistence.storageClass   | Storage class for Persistent Volume Claims. If undefined (the default) or set to null, no storageClassName spec is set, choosing the default provisioner e.g., gp2 on AWS, standard on GKE).                | ""                              |
| postgresql.primary.persistence.accessModes    | PVC Access Mode for PostgreSQL volume.                                                                                                                                                                      | ReadWriteOnce                   |
| postgresql.primary.persistence.size           | Size of data volume.                                                                                                                                                                                        | 8Gi                             |
| **Backup Configuration**                      |                                                                                                                                                                                                             |                                 |
| postgresql.backup.enabled                     | Enable daily logical dumps of the database.                                                                                                                                                                 | false                           |
| postgresql.backup.cronjob.schedule            | Cron schedule for backups (@daily, @hourly).                                                                                                                                                                | "@daily"                        |
| postgresql.backup.cronjob.nodeSelector        | Node labels for PostgreSQL backup CronJob pod assignment. See https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/ for more details.                                                 | { }                             |
| postgresql.backup.cronjob.resources           | Backup pod resource requests/limits.                                                                                                                                                                        | { }                             |
| postgresql.backup.cronjob.storage.size        | PVC size allocated for backups.                                                                                                                                                                             | 8Gi                             |
| **Volume Permissions**                        |                                                                                                                                                                                                             |                                 |
| postgresql.volumePermissions.image.repository | Helper image repository for volume permissions. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164             | bitnamilegacy/os-shell          |
| **Monitoring & Metrics**                      |                                                                                                                                                                                                             |                                 |
| postgresql.metrics.enabled                    | Enable Prometheus Exporter for PostgreSQL metric.                                                                                                                                                           | false                           |
| postgresql.metrics.image.repository           | Postgres exporter image repository for Prometheus metrics. Uses Bitnami Legacy to ensure compatibility after Bitnami’s registry changes in August 2025. See https://github.com/bitnami/charts/issues/35164  | bitnamilegacy/postgres-exporter |
| postgresql.metrics.resources                  | Resource requests/limits for PostgreSQL exporter.                                                                                                                                                           | { }                             |
| postgresql.metrics.service.ports.metrics      | Prometheus Exporter port for PostgreSQL metrics.                                                                                                                                                            | 9187                            |

🔗 See official Bitnami PostgreSQL Artifact Hub [page](https://artifacthub.io/packages/helm/bitnami/postgresql/15.5.38) for more details.

### External PostgreSQL Configuration

By default, the chart installs Bitnami PostgreSQL `postgresql.enabled: true`, provisioning a single-node instance with configurable storage, backups, and monitoring options. 
For users with an existing PostgreSQL instance, such as AWS RDS, Google Cloud SQL, or an on-premises database, TBMQ can be configured to connect externally.
To do this, disable the built-in PostgreSQL `postgresql.enabled: false` and specify connection details in the `externalPostgresql` section.

Please refer to the table below to review external PostgreSQL configuration parameters, their descriptions, and default values.

| Parameter                    | Description                                                     | Default Value             |
|------------------------------|-----------------------------------------------------------------|---------------------------|
| externalPostgresql.host	     | Hostname or IP of the external PostgreSQL server.               | ""                        |
| externalPostgresql.port	     | PostgreSQL server port.                                         | 5432                      |
| externalPostgresql.username	 | Username for PostgreSQL authentication.                         | "postgres"                |
| externalPostgresql.password	 | Password for PostgreSQL authentication (change for production). | "postgres"                |
| externalPostgresql.database	 | PostgreSQL database name for TBMQ.                              | "thingsboard_mqtt_broker" |

#### External PostgreSQL Configuration Example:

```yaml
postgresql:
  enabled: false

externalPostgresql:
  host: "your-db-host"
  port: 5432
  username: "your-username"
  password: "your-password"
  database: "thingsboard_mqtt_broker"
```

This disables the Bitnami PostgreSQL chart and connects to the provided external database.

### Load Balancer Configuration

The TBMQ Helm chart provides configuration options for Ingress and LoadBalancer services, assuming that an Ingress Controller or Load Balancer exists in the Kubernetes cluster.

This chart does not deploy a Load Balancer or Ingress Controller (such as AWS ALB, Azure Application Gateway, or GCP HTTPS Load Balancer).
Instead, it creates Kubernetes Ingress and Service resources that integrate with pre-existing networking components provided by the cloud provider or Kubernetes itself.

For the first release, we designed a single configuration format for load balancers, ensuring consistency across:
- **AWS:** Uses Application Load Balancer (ALB) for HTTP(S) traffic and Network Load Balancer (NLB) for MQTT(S) traffic.
- **Azure:** Uses Application Gateway for HTTP(S) traffic and Azure Load Balancer for MQTT(S) traffic.
- **GCP:** Uses HTTPS Load Balancer for HTTP(S) traffic and Network Load Balancer (NLB) for MQTT(S) traffic.
- **Nginx:** Use basic Kubernetes Ingress for HTTP and a LoadBalancer service for MQTT(S) without cloud-specific integrations.

> ⚠️ **Warning:** Some features may not be available for all loadbalancer types.
Certain settings, e.g., TLS termination for NLB are not supported or not yet implemented for some cloud providers.

Please refer to the table below to review loadbalancer parameters, their descriptions, and default values.

| Parameter                                               | Description                                                                                                                                                                                                                                                                                                                                       | Default Value            |
|---------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------|
| **General Load Balancer Settings**                      |                                                                                                                                                                                                                                                                                                                                                   |                          |
| loadbalancer.type                                       | Defines the type of load balancer integration. Allowed values: "aws", "azure", "gcp", "nginx".                                                                                                                                                                                                                                                    | "nginx"                  |
| loadbalancer.http.enabled                               | Enables the HTTP Load Balancer (Application Layer - L7).                                                                                                                                                                                                                                                                                          | true                     |
| loadbalancer.mqtt.enabled                               | Enables the MQTT Load Balancer (Transport Layer - L4).                                                                                                                                                                                                                                                                                            | true                     |
| **HTTP(S) Configuration**                               |                                                                                                                                                                                                                                                                                                                                                   |                          |
| loadbalancer.http.ssl.enabled                           | Enables HTTPS termination at the load balancer level.                                                                                                                                                                                                                                                                                             | false                    |
| loadbalancer.http.ssl.certificateRef                    | SSL certificate reference (depends on loadbalancer type).<br /><ul><li>AWS: The ACM certificate ARN for ALB.</li><li>Azure: The `appgw-ssl-certificate` value in Application Gateway.</li><li>GCP: The name of the `ManagedCertificate` resource.</li><li>Nginx: Not implemented.</li></ul>                                                       | ""                       |
| loadbalancer.http.ssl.domains                           | List of domains for HTTPS traffic.<br /><ul><li>AWS: Not used in Ingress. Domains are part of the ACM certificate specified in `certificateRef`.</li><li>Azure: Not used in Ingress. Managed directly in Application Gateway.</li><li>GCP: Required in Ingress. Used for `ManagedCertificate` issuance.</li><li>Nginx: Not implemented.</li></ul> | ["www.example.com"]      |
| loadbalancer.http.ssl.staticIP                          | Static IP address for the GCP HTTP(S) load balancer. Required for GCP. Ignored for other types.                                                                                                                                                                                                                                                   | "tbmq-http-lb-address"   |
| **MQTT(S) Configuration**                               |                                                                                                                                                                                                                                                                                                                                                   |                          |
| loadbalancer.mqtt.mutualTls.enabled                     | Enables two-way TLS (Mutual TLS or mTLS) at the TBMQ app level. Both the client and server authenticate each other. Requires certificate + private key. TLS Termination is ignored if this is enabled.                                                                                                                                            | false                    |
| loadbalancer.mqtt.mutualTls.configMapName               | Name of the ConfigMap containing server certificate and private key. Creation steps described further.                                                                                                                                                                                                                                            | "tbmq-node-mqtts-config" |
| loadbalancer.mqtt.mutualTls.privateKeyPasswordSecret    | Name of the Secret storing the private key password. Required only if your key is password-protected.                                                                                                                                                                                                                                             | ""                       |
| loadbalancer.mqtt.mutualTls.privateKeyPasswordSecretKey | Key inside the Secret storing the private key password.                                                                                                                                                                                                                                                                                           | "key_password"           |
| loadbalancer.mqtt.tlsTermination.enabled                | Enables one-way TLS Termination (L4, load balancer level).<br /><ul><li>AWS: Supported via NLB with ACM certificate.</li><li>Azure: Not supported at Azure LB level.</li><li>GCP: Not supported at GCP Network LB level.</li><li>Nginx: Not implemented.</li></ul>                                                                                | false                    |
| loadbalancer.mqtt.tlsTermination.certificateRef         | TLS certificate reference for MQTT load balancer.<br /><ul><li>AWS: ACM certificate ARN for NLB.</li><li>Azure: Not applicable (ignored).</li><li>GCP: Not applicable (ignored).</li><li>Nginx: Not implemented (ignored).</li></ul>                                                                                                              | ""                       |


### Configuring Mutual TLS (mTLS) for MQTT

Mutual TLS (mTLS) ensures both the client and server authenticate each other before establishing an MQTT connection.
To configure this, we need to obtain a valid (signed) TLS certificate and configure it in the TBMQ. 
The main advantage of this option is that you may use it in combination with **_X.509 Certificate Chain_** MQTT client credentials. 

Before enabling mTLS, we need:

- Server certificate in **_.pem_** format.
- Private key in **_.pem_** format.
- Password for the private key. Required only if your private key is password-protected.

#### Creating a Kubernetes ConfigMap for mTLS Certificates

The ConfigMap name should match `loadbalancer.mqtt.mutualTls.configMapName`. Use the following command to create a ConfigMap:

```bash
kubectl create configmap tbmq-node-mqtts-config \
    --from-file=server.pem=/path/to/server.pem \
    --from-file=mqttserver_key.pem=/path/to/mqttserver_key.pem \
    -o yaml --dry-run=client | kubectl apply -f -
```

> ⚠️ **Warning:** Replace `/path/to/server.pem` and `/path/to/mqttserver_key.pem` with the actual paths to your certificate and private key files.

This will create a ConfigMap named **_tbmq-node-mqtts-config_**, which TBMQ will use to load certificates.

#### Storing the Private Key Password in a Kubernetes Secret (Optional)

If your private key requires a password, you need to store it in a Kubernetes Secret.
The Secret name should match `loadbalancer.mqtt.mutualTls.privateKeyPasswordSecret`,
and the key inside the Secret should match `loadbalancer.mqtt.mutualTls.privateKeyPasswordSecretKey`.
Use the following command to create a Secret:

```bash
kubectl create secret generic mqtt-tls-secret \
--from-literal=key_password="YOUR_KEY_PASSWORD" \
-o yaml --dry-run=client | kubectl apply -f -
```

> ⚠️ **Warning:** Replace `YOUR_KEY_PASSWORD` with the actual password for your private key.

This will create a Secret named **_mqtt-tls-secret_**.

> 💡 **Tip:** If you already have an existing Secret with a different key name, you can use it by specifying its name and key in the configuration.

Example configuration in `values.yaml`

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

## Uninstalling Chart

To uninstall the TBMQ cluster, use the following command:

```bash
helm delete my-tbmq-cluster -n <namespace_name>
```

This command removes all the TBMQ components associated with the chart from the specified namespace `<namespace_name>`.

> ⚠️ **Warning:** `helm delete` command removes the logical resources of the TBMQ cluster. To completely remove all persistent data, you may need to additionally delete the Persistent Volume Claims (PVCs) after uninstallation.

```shell
kubectl delete pvc -l app.kubernetes.io/instance=my-tbmq-cluster
```