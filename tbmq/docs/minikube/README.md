# TBMQ Helm Chart — Minikube Deployment Guide

This guide walks you through deploying TBMQ on Minikube with:

- **PostgreSQL** via [CrunchyData PGO](https://github.com/CrunchyData/postgres-operator) (PostgreSQL 17)
- **Kafka** via [Strimzi Operator](https://strimzi.io/) (Apache Kafka 4.0.0, KRaft mode)
- **Valkey** via [official Valkey Helm chart](https://github.com/valkey-io/valkey-helm) (standalone)

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed and running
- [Helm](https://helm.sh/docs/intro/install/) v3.10+
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured to use your Minikube cluster

Start Minikube with sufficient resources:

```bash
minikube start --cpus=4 --memory=8192
```

Create the namespace:

```bash
kubectl create namespace thingsboard-mqtt-broker
```

---

## Step 1: Deploy PostgreSQL (CrunchyData PGO)

### Install the PGO operator

```bash
helm install pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
  --namespace thingsboard-mqtt-broker
```

Wait for the operator pod to be ready:

```bash
kubectl wait --for=condition=Ready pod \
  -l postgres-operator.crunchydata.com/control-plane=pgo \
  -n thingsboard-mqtt-broker --timeout=180s
```

### Create a PostgreSQL cluster

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: tbmq-db
  namespace: thingsboard-mqtt-broker
spec:
  postgresVersion: 17
  instances:
    - name: instance1
      replicas: 1
      dataVolumeClaimSpec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
      resources:
        limits:
          cpu: "500m"
          memory: "512Mi"
  users:
    - name: postgres
      databases:
        - thingsboard_mqtt_broker
  backups:
    pgbackrest:
      repos:
        - name: repo1
          volume:
            volumeClaimSpec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 1Gi
EOF
```

Wait for the cluster to be ready:

```bash
kubectl wait --for=condition=Ready pod -l postgres-operator.crunchydata.com/cluster=tbmq-db \
  -n thingsboard-mqtt-broker --timeout=300s
```

### Verify

PGO auto-generates credentials in a Secret named `tbmq-db-pguser-postgres`. You can verify:

```bash
# Check the service
kubectl get svc -n thingsboard-mqtt-broker | grep tbmq-db

# Retrieve the generated password
kubectl get secret tbmq-db-pguser-postgres -n thingsboard-mqtt-broker \
  -o go-template='{{.data.password | base64decode}}'
```

**Connection details for TBMQ:**
- Host: `tbmq-db-primary`
- Port: `5432`
- Database: `thingsboard_mqtt_broker`
- Secret: `tbmq-db-pguser-postgres` (key: `password`)

---

## Step 2: Deploy Kafka (Strimzi Operator)

### Install the Strimzi operator

```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo update

helm install strimzi strimzi/strimzi-kafka-operator \
  --namespace thingsboard-mqtt-broker \
  --version 0.50.0
```

Wait for the operator to be ready:

```bash
kubectl wait --for=condition=Ready pod -l name=strimzi-cluster-operator \
  -n thingsboard-mqtt-broker --timeout=120s
```

### Create a Kafka cluster

This deploys a 3-node KRaft cluster (no ZooKeeper) with combined controller+broker roles:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata:
  name: combined
  namespace: thingsboard-mqtt-broker
  labels:
    strimzi.io/cluster: tbmq-kafka
spec:
  replicas: 3
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 1Gi
        deleteClaim: false
  resources:
    requests:
      memory: "1Gi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"
---
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata:
  name: tbmq-kafka
  namespace: thingsboard-mqtt-broker
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 4.0.0
    metadataVersion: "4.0"
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      auto.create.topics.enable: false
      default.replication.factor: 2
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF
```

Wait for the Kafka cluster to be ready (this may take a few minutes):

```bash
kubectl wait kafka/tbmq-kafka --for=condition=Ready \
  -n thingsboard-mqtt-broker --timeout=300s
```

### Verify

```bash
# Check all Kafka pods are running
kubectl get pods -n thingsboard-mqtt-broker -l strimzi.io/cluster=tbmq-kafka

# Check the bootstrap service
kubectl get svc tbmq-kafka-kafka-bootstrap -n thingsboard-mqtt-broker
```

**Connection details for TBMQ:**
- Bootstrap servers: `tbmq-kafka-kafka-bootstrap:9092`

---

## Step 3: Deploy Valkey

### Install Valkey (standalone, no auth)

```bash
helm repo add valkey https://valkey.io/valkey-helm/
helm repo update

helm install valkey valkey/valkey \
  --namespace thingsboard-mqtt-broker \
  --version 0.9.3
```

Wait for the pod to be ready:

```bash
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=valkey \
  -n thingsboard-mqtt-broker --timeout=120s
```

### Verify

```bash
kubectl get svc valkey -n thingsboard-mqtt-broker
```

**Connection details for TBMQ:**
- Host: `valkey`
- Port: `6379`
- Connection type: `standalone`
- Auth: disabled

---

## Step 4: Deploy TBMQ

### Create a values file

Create `minikube-values.yaml`:

```yaml
tbmq:
  image:
    tag: 2.3.0
  statefulSet:
    replicas: 1

tbmq-ie:
  image:
    tag: 2.3.0
  statefulSet:
    replicas: 1

postgresql:
  host: "tbmq-db-primary"
  port: 5432
  database: "thingsboard_mqtt_broker"
  username: "postgres"
  existingSecret: "tbmq-db-pguser-postgres"
  existingSecretPasswordKey: "password"

kafka:
  bootstrapServers: "tbmq-kafka-kafka-bootstrap:9092"

redis:
  connectionType: "standalone"
  host: "valkey"
  port: 6379
  usePassword: false

loadbalancer:
  type: "nginx"
  http:
    enabled: true
  mqtt:
    enabled: true
```

### Install the chart

```bash
helm install tbmq ../../ -f minikube-values.yaml \
  --set installation.installDbSchema=true \
  --namespace thingsboard-mqtt-broker
```

> Pass `installation.installDbSchema=true` via `--set` on the **first install only**.
> Do not put it in `minikube-values.yaml` — the post-install hook is bound to
> `post-install,post-upgrade`, so persisting the flag would re-fire the install
> Pod on every `helm upgrade` and corrupt an already-populated schema.

### Verify

```bash
# Wait for the broker pod
kubectl wait --for=condition=Ready pod/tbmq-tbmq-node-0 \
  -n thingsboard-mqtt-broker --timeout=300s

# Wait for the integration executor pod
kubectl wait --for=condition=Ready pod/tbmq-tbmq-ie-0 \
  -n thingsboard-mqtt-broker --timeout=300s

# Check all pods are running
kubectl get pods -n thingsboard-mqtt-broker
```

The broker StatefulSet now provisions a 1Gi PVC per Pod for `/data`. On Minikube the
default `storage-provisioner` addon satisfies it automatically:

```bash
kubectl get pvc -n thingsboard-mqtt-broker -l app=tbmq-tbmq-node
# Expected: tbmq-tbmq-node-data-tbmq-tbmq-node-0 Bound
```

To opt out (CE only — see chart README "Persistence"), set `tbmq.persistence.enabled=false`
in `minikube-values.yaml`.

> **Note on the install Pod:** the chart's post-install hook creates a one-shot
> Pod named `tbmq-install-pod`. Helm deletes it as soon as it succeeds (or
> fails) — `hook-delete-policy: hook-succeeded,hook-failed`. If you want to
> watch its logs, run `kubectl logs tbmq-install-pod -n thingsboard-mqtt-broker -f`
> immediately after `helm install`, or use `helm install --debug` to stream
> hook output to your terminal.

### Access the TBMQ UI

**Option A: Port-forward (simplest, recommended for Minikube)**

```bash
kubectl port-forward svc/tbmq-tbmq-node 8083:8083 -n thingsboard-mqtt-broker
```

Open http://localhost:8083. Leave the command running; close it with `Ctrl-C`
when you're done.

**Option B: Ingress addon (browse via the Minikube IP)**

The chart creates an `Ingress` resource (`tbmq-http-lb`) but does NOT bring an
Ingress Controller. On Minikube, enable the bundled NGINX controller addon:

```bash
minikube addons enable ingress
# wait for the controller to be ready
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  -n ingress-nginx --timeout=180s
```

Then browse to `http://<minikube ip>/` — find it with `minikube ip`. Note that
the chart's default Ingress matches `host: *` on port 80, which will work as
long as no other Ingress in the cluster claims `/`. If you also want the MQTT
LoadBalancer Service to get an external IP, run `minikube tunnel` in a
separate terminal (it asks for sudo).

Default credentials: `sysadmin@thingsboard.org` / `sysadmin`

---

## Step 5: Upgrade CE to PE (Cross-Edition Migration)

This step migrates the CE deployment from Step 4 to **Professional Edition (PE)** on
the same TBMQ version. PE images are published publicly on Docker Hub
(`thingsboard/tbmq-pe-node`, `thingsboard/tbmq-pe-integration-executor`); the only
new requirement compared to CE is a valid PE license.

### 5.1 Create a Secret with your PE license

```bash
kubectl create secret generic tbmq-license \
  --from-literal=license-key=YOUR_LICENSE_KEY \
  -n thingsboard-mqtt-broker
```

### 5.2 Reference the Secret in `minikube-pe-values.yaml`

This repo ships an example PE values file at
`tbmq/docs/minikube/minikube-pe-values.yaml`. Open it and uncomment the
`existingSecret` line so the broker mounts your license:

```yaml
license:
  secret: ""
  existingSecret: tbmq-license
```

`minikube-pe-values.yaml` already pins the PE image repos (`tbmq-pe-node`,
`tbmq-pe-integration-executor`) and the matching `2.3.0PE` tags, and points to the
same Postgres / Kafka / Valkey services you deployed in Steps 1–3.

### 5.3 Run the helm upgrade

```bash
helm upgrade tbmq ../../ -f minikube-pe-values.yaml \
  --set upgrade.upgradeDbSchema=true \
  --set upgrade.fromVersion=ce \
  -n thingsboard-mqtt-broker
```

What happens:

- The **pre-upgrade Job** runs with the PE broker image, `UPGRADE_TB=true` and
  `FROM_VERSION=ce`. The PE entrypoint script forwards `FROM_VERSION` as
  `-Dinstall.upgrade.from_version=ce` to the install application, which switches
  the migration into CE→PE mode and rewrites the CE schema as PE.
- Once the migration succeeds, Helm rolls the **`tbmq-tbmq-node`** and
  **`tbmq-tbmq-ie`** StatefulSets onto the PE images. The broker validates the
  license on startup (the IE and the upgrade Job do not validate the license).
- The broker writes a per-Pod license cache file under
  `/data/tbmq-instance-license-$(TB_SERVICE_ID).data`.

### 5.4 Verify

```bash
# Wait for the broker pod to come back Ready on the PE image
kubectl wait --for=condition=Ready pod/tbmq-tbmq-node-0 \
  -n thingsboard-mqtt-broker --timeout=300s
kubectl wait --for=condition=Ready pod/tbmq-tbmq-ie-0 \
  -n thingsboard-mqtt-broker --timeout=300s

# Image should now be the PE one
kubectl get pod tbmq-tbmq-node-0 -n thingsboard-mqtt-broker \
  -o jsonpath='{.spec.containers[0].image}'
# expected: thingsboard/tbmq-pe-node:2.3.0PE

# tb_schema_settings.product should now be PE
PG_POD=$(kubectl get pod -n thingsboard-mqtt-broker \
  -l postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n thingsboard-mqtt-broker "$PG_POD" -c database -- \
  psql -U postgres -d thingsboard_mqtt_broker -c "SELECT * FROM tb_schema_settings;"
# expected: product = PE
```

### 5.5 After the migration succeeds

**Drop `upgrade.fromVersion=ce`** on subsequent PE→PE upgrades — leaving it set
would cause the upgrade Job to attempt the CE→PE migration against an already-PE
schema and fail. The flag is single-use for the cross-edition migration.

> If you only want to do a fresh PE install (no CE→PE migration), use
> `minikube-pe-values.yaml` directly with `helm install` instead — same way as the
> Step 4 CE flow, but pointing at this file and adding
> `--set installation.installDbSchema=true` on the first install.

---

## Cleanup

```bash
# Remove TBMQ
helm uninstall tbmq -n thingsboard-mqtt-broker

# Remove Valkey
helm uninstall valkey -n thingsboard-mqtt-broker

# Remove Kafka cluster and Strimzi operator
kubectl delete kafka tbmq-kafka -n thingsboard-mqtt-broker
kubectl delete kafkanodepool combined -n thingsboard-mqtt-broker
helm uninstall strimzi -n thingsboard-mqtt-broker

# Remove PostgreSQL cluster and PGO operator
kubectl delete postgrescluster tbmq-db -n thingsboard-mqtt-broker
helm uninstall pgo -n thingsboard-mqtt-broker

# Remove namespace
kubectl delete namespace thingsboard-mqtt-broker
```
