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
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=pgo \
  -n thingsboard-mqtt-broker --timeout=120s
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
apiVersion: kafka.strimzi.io/v1beta2
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
apiVersion: kafka.strimzi.io/v1beta2
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
installation:
  installDbSchema: true

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
  --namespace thingsboard-mqtt-broker
```

### Verify

```bash
# Wait for TBMQ pods
kubectl wait --for=condition=Ready pod -l app -n thingsboard-mqtt-broker --timeout=300s

# Check all pods are running
kubectl get pods -n thingsboard-mqtt-broker
```

### Access the TBMQ UI

```bash
# Port-forward the HTTP service
kubectl port-forward svc/$(kubectl get svc -n thingsboard-mqtt-broker -l app -o jsonpath='{.items[0].metadata.name}') \
  8083:8083 -n thingsboard-mqtt-broker
```

Open http://localhost:8083 in your browser.

Default credentials: `sysadmin@thingsboard.org` / `sysadmin`

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
