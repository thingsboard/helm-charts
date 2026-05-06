# TBMQ Helm Chart End-to-End Verification — Design

**Date:** 2026-05-06
**Branch:** `tbmq/2.3`
**Chart:** `tbmq/` — chart version `2.0.0`, appVersion `2.3.0`
**Author:** dlandiak

## 1. Mission

Verify the TBMQ Helm chart against a real Kubernetes runtime (Minikube) for every
configuration permutation the chart actually exposes today. Each scenario performs
a clean install, exercises the broker with a fixed smoke test, and tears down. Defects
discovered during verification are fixed inline on `tbmq/2.3` and re-tested. Chart
documentation is updated in the same commit as any behavior change so docs cannot drift.

A small chart change — adding `tbmq.persistence` so the broker's `/data` directory
can be backed by a `volumeClaimTemplate` — is bundled with the campaign because the
PE license-instance-data file must survive Pod recreation. The reference PE manifest
(`tbmq-pe-k8s`) already uses a PVC for `/data`; the chart should match.

## 2. Scope

### In scope

- All chart-exposed configuration permutations:
  - Dependency wiring (Postgres, Kafka, Redis-compatible).
  - Credential paths (Secret vs inline) for Postgres, Redis, PE license, Docker registry.
  - Redis `cluster` vs `standalone` connection modes.
  - 3-tier ConfigMap override hierarchy (`existingConfigMap` > `existingJavaOpts/Logback` > defaults), broker and IE independently.
  - `customEnv` overrides on broker and IE.
  - Replica counts (singleton, default HA=2, scaled HA=3).
  - Image pull secret presence (chart-managed vs pre-created vs absent).
  - Checksum annotations (broker and IE independently).
  - Helm install / config-change `helm upgrade` / no-op `upgrade.upgradeDbSchema=true` upgrade.
- Load balancer flavor `nginx` live; flavors `aws` / `azure` / `gcp` covered by
  `helm template` lint only (no cloud cluster available on minikube).
- One PE install per license credential path (`license.secret` inline,
  `license.existingSecret` pre-created), license-persistence behavior across pod
  recreation, license-checksum-driven rolling restart, missing-license failure mode.
- A new chart change: optional PVC for `/data` (`tbmq.persistence` block, default-on,
  matching the reference PE manifest).

### Out of scope (deferred to report only — not tested live)

- Real cross-version `helm upgrade` with a schema migration (chart only ships at
  appVersion 2.3.0; older-image installs against the new dependency stack are not
  guaranteed to work and were already validated separately).
- CE → PE cross-edition migration (already validated separately; per task brief).
- Chart 1.x → 2.0.0 upgrade (already validated separately; per task brief).
- TLS / mTLS / MQTTS / WSS / Postgres-TLS / Kafka-SASL / Valkey-AUTH (per the
  conditional gate in the task brief — none of those template paths changed since
  the baseline commit `14ad95661c831b498b00b344c6bf9d006e92702c`).
- WebSocket MQTT smoke (per user direction — "if MQTT works then MQTT-over-WS works").
- ArgoCD live execution (no ArgoCD controller available; covered by template lint).
- Chart features the chart does not expose today: PVC for IE, NodePort, PDB,
  ServiceAccount/RBAC, custom storageClass on IE, etc. Adding these is out of scope
  for this campaign.
- Variations of the 3rd-party stack itself (Redis cluster mode, Redis with auth,
  managed Postgres, etc.) — only the canonical `tbmq/docs/minikube` stack is used
  live. Cluster-vs-standalone Redis and Redis auth are covered via Phase 0 template
  lint only.

## 3. Approach

Phased execution: lint-then-live, with the chart change landing before live runs so
no live scenario has to be re-run because of the persistence change.

- **Phase 0 — Template-only sweep.** `helm template` every scenario, validate YAML,
  assert on rendered manifests. Catches rendering defects without paying minikube
  install cost. Cloud LB types and ArgoCD live here permanently.
- **Phase 1 — Chart change for `tbmq.persistence`.** Implement the new values block
  + template branch, update `values.yaml` comments, README, and `Chart.yaml`
  changelog in the same commit. Re-render Phase 0 cases that touch the broker
  StatefulSet under both `enabled: true` and `enabled: false`.
- **Phase 2 — Live CE matrix on minikube.** Single shared cluster; namespace per
  scenario; PGO, Strimzi, and Valkey operators installed cluster-wide once. Each
  scenario provisions its own `PostgresCluster` / `Kafka` / `Valkey` release in its
  namespace. Smoke after every install. Fix-and-rerun on defect.
- **Phase 3 — Live PE license suite.** PE overlay + the test license
  `xGekoaiFH7MjFqxARJz9yKrc` against `https://pe.tbqa.cloud:1443`. Test license
  validation, persistence behavior across pod recreation (PVC enabled and disabled
  for regression), checksum-driven rolling restart, and the missing-license failure
  mode.
- **Phase 4 — Verification report.** `VERIFICATION_REPORT.md` at the repo root.

Every live scenario reuses the canonical 3rd-party stack from `tbmq/docs/minikube/README.md`
(CrunchyData PGO, Strimzi Kafka, standalone no-auth Valkey). The 3rd-party stack itself is
not varied between scenarios.

## 4. Scenario matrix

Naming: `T<n>` = template-only (Phase 0), `L<n>` = live CE (Phase 2),
`P<n>` = live PE (Phase 3).

### Phase 0 — Template-only (`helm template …` + assertions)

For every case: render the chart, validate YAML, assert on rendered manifests
using `yq` / `grep -F` / file presence checks.

#### Credential paths

| ID | Override | Assertion |
|---|---|---|
| T1 | minimum required values; no `existing*Secret` | YAML valid; `*-postgres-secret` and `*-redis-secret` render; broker references them. |
| T2 | `postgresql.existingSecret=mypg`, `postgresql.existingSecretPasswordKey=password` | `*-postgres-secret` does NOT render; broker references `mypg`. |
| T3 | `postgresql.password=p` (no existingSecret) | `*-postgres-secret` renders with the password; broker references it. |
| T6 | `redis.usePassword=false` | `REDIS_PASSWORD` env absent; `*-redis-secret` not rendered. |
| T7 | `redis.existingSecret=myr`, `redis.existingSecretPasswordKey=p` | `*-redis-secret` does NOT render; broker references `myr`. |

#### Redis modes

| ID | Override | Assertion |
|---|---|---|
| T4 | `redis.connectionType=cluster`, `redis.nodes=r1:6379,r2:6379` | Cluster topology refresh keys present in `-redis-config`; standalone keys absent. |
| T5 | `redis.connectionType=standalone`, `redis.host=v`, `redis.port=6379` | Standalone host/port keys present; cluster keys absent. |

#### ConfigMap override hierarchy

| ID | Override | Assertion |
|---|---|---|
| T8 | `tbmq.existingConfigMap=myconf` | `*-tbmq-node-default-config` and `*-tbmq-node-default-logback-config` do NOT render; broker volumes reference `myconf`. |
| T9 | `tbmq.existingJavaOptsConfigMap=myjopts` (no existingConfigMap) | Default Java-opts CM does NOT render; default logback CM DOES render. |
| T10 | `tbmq.existingLogbackConfigMap=mylog` (no existingConfigMap) | Default logback CM does NOT render; default Java-opts CM DOES render. |
| T11 | `tbmq-ie.existingConfigMap=myconf-ie` | IE default CMs do NOT render; IE volumes reference `myconf-ie`. |
| T12 | `tbmq-ie.existingJavaOptsConfigMap=myjopts-ie` | IE default Java-opts CM does NOT render; IE default logback CM DOES render. |
| T13 | `tbmq-ie.existingLogbackConfigMap=mylog-ie` | IE default logback CM does NOT render; IE default Java-opts CM DOES render. |

#### `customEnv`

| ID | Override | Assertion |
|---|---|---|
| T14 | `tbmq.customEnv.FOO=bar` | `FOO=bar` appears in `-tbmq-custom-env` CM; `envFrom` ordering puts custom-env last. |
| T15 | `tbmq-ie.customEnv.FOO=bar` | `FOO=bar` appears in `-tbmq-ie-custom-env` CM. |

#### Annotations

| ID | Override | Assertion |
|---|---|---|
| T16 | `tbmq.enableChecksumAnnotations=false` | Broker pod template has no `checksum/*` annotations. |
| T17 | `tbmq-ie.enableChecksumAnnotations=false` | IE pod template has no `checksum/*` annotations. |
| T18 | `tbmq.statefulSet.annotations.foo=bar`, `tbmq.annotations.baz=qux` | StatefulSet `metadata.annotations.foo=bar`; pod template `metadata.annotations.baz=qux`. |

#### Install / upgrade hooks

| ID | Override | Assertion |
|---|---|---|
| T19 | `installation.installDbSchema=true` | Install Pod renders; `helm.sh/hook=post-install,post-upgrade`; env `INSTALL_TB=true`; `imagePullSecrets` matches `tbmq.imagePullSecret`. |
| T20 | (default) | Install Pod does NOT render. |
| T21 | `installation.argocd=true` + `installation.installDbSchema=true` | Install Pod has `argocd.argoproj.io/hook: Sync`; no Helm hook annotations. |
| T22 | `--is-upgrade --set upgrade.upgradeDbSchema=true` | Pre-upgrade Job renders; `helm.sh/hook=pre-upgrade`; `ttlSecondsAfterFinished=300`; env `UPGRADE_TB=true`; `imagePullSecrets` matches `tbmq.imagePullSecret`. |
| T23 | `upgrade.upgradeDbSchema=true` without `--is-upgrade` | Pre-upgrade Job does NOT render. |
| T24 | `--is-upgrade --set upgrade.upgradeDbSchema=true --set upgrade.fromVersion=ce` | Pre-upgrade Job has env `FROM_VERSION=ce`. |
| T25 | `--is-upgrade --set upgrade.upgradeDbSchema=true --set upgrade.argocd=true` | Pre-upgrade Job has `argocd.argoproj.io/hook: PreSync`; no Helm hook annotations. |

#### License

| ID | Override | Assertion |
|---|---|---|
| T26 | `license.secret=foo` | `<release>-tbmq-license-secret` renders; broker has `TBMQ_LICENSE_SECRET` + `TBMQ_LICENSE_INSTANCE_DATA_FILE` env; `checksum/license-secret` annotation present. |
| T27 | `license.existingSecret=mylic` | License Secret does NOT render; broker references `mylic`. |
| T28 | `license.existingSecret=mylic`, `license.existingSecretLicenseKey=customKey` | Broker `TBMQ_LICENSE_SECRET.valueFrom.secretKeyRef.key=customKey`. |
| T29 | `license.secret=foo`, `license.instanceDataFile=/custom/path.data` | Broker `TBMQ_LICENSE_INSTANCE_DATA_FILE=/custom/path.data`. |
| T30 | (license configured) | IE StatefulSet, install Pod, pre-upgrade Job do NOT have `TBMQ_LICENSE_*` env vars. |
| T31 | (no license values) | No license env on broker; no license Secret rendered; no `checksum/license-secret` annotation. |

#### Image pull

| ID | Override | Assertion |
|---|---|---|
| T32 | `dockerAuth.username=""` | `regcred` Secret does NOT render. Broker / IE / install / upgrade still reference the pull-secret name. |
| T33 | `dockerAuth.username=u`, `dockerAuth.password=p` | `regcred` Secret renders with valid `kubernetes.io/dockerconfigjson`. |
| T34 | `tbmq.imagePullSecret=other`, `dockerAuth.username=u` | Chart-managed Secret name = `other` (not `regcred`). |

#### Load balancer

| ID | Override | Assertion |
|---|---|---|
| T35 | `loadbalancer.type=nginx` (default) | Ingress + LB Service render; selectors point to broker; `http.enabled=false` suppresses Ingress; `mqtt.enabled=false` suppresses LB Service. |
| T36 | `loadbalancer.type=aws` | Ingress has ALB-specific annotations; MQTT Service has NLB annotations; `tlsTermination.enabled=true` injects ACM cert annotations. |
| T37 | `loadbalancer.type=azure` | Ingress has appgw annotations; MQTT Service has Azure-LB annotations. |
| T38 | `loadbalancer.type=gcp` | Ingress + ManagedCertificate handled; MQTT Service has GCP NLB annotations; `staticIP` honored. |
| T39 | provider default + user `loadbalancer.http.annotations.x=user` (same key as provider default) | User value wins on conflict. |

#### Singleton mode

| ID | Override | Assertion |
|---|---|---|
| T40 | `tbmq.statefulSet.replicas=1` | Broker env `TB_SERVICE_SINGLETON_MODE=true`. `replicas=2` (default) ⇒ `false`. |

### Phase 1 — Chart change

See §5.

### Phase 2 — Live CE on minikube

All scenarios use the canonical `docs/minikube/minikube-values.yaml` as the base
overlay. Per-scenario overlay file layered on top.

| ID | Scenario | Key overrides |
|---|---|---|
| L1 | Default install (HA, 2+2) | base only |
| L2 | Singleton broker | `tbmq.statefulSet.replicas=1` |
| L3 | 3-replica broker, kill broker pod, session resume | `tbmq.statefulSet.replicas=3` |
| L4 | `tbmq.existingConfigMap` (combined) | pre-create CM with `conf` + `logback` keys; `tbmq.existingConfigMap=myconf` |
| L5 | Split `existingJavaOptsConfigMap` + `existingLogbackConfigMap` | pre-create both CMs |
| L6 | `tbmq.customEnv` runtime | add `STATS_PRINT_INTERVAL_MS=15000`; verify in-pod env |
| L7 | Postgres `existingSecret` (PGO canonical) | `postgresql.existingSecret=tbmq-db-pguser-postgres` (already the default in `minikube-values.yaml`) |
| L8 | Postgres inline password | read PGO password, set `postgresql.password=<value>`; clear `existingSecret` |
| L9 | Helm upgrade — config change | install L1; upgrade with `replicas: 3` and `customEnv` change; pods roll; smoke passes |
| L10 | Helm upgrade — swap inline → existingSecret | install L8; upgrade swapping to PGO `existingSecret`; broker reconnects cleanly |
| L11 | Helm upgrade — no-op `upgradeDbSchema=true` | install L1; upgrade `--set upgrade.upgradeDbSchema=true`; pre-upgrade Job runs and exits cleanly; broker rolls minimally |
| L12 | Pod restart resilience | L1; `kubectl delete pod my-tbmq-tbmq-node-0`; verify recreate; smoke |
| L13 | Resources requests/limits | non-empty `tbmq.resources` + `tbmq-ie.resources`; verify on container spec |
| L14 | No imagePullSecret | `dockerAuth.username=""` (default); regcred Secret not created; public images pull cleanly |
| L15 | `tbmq-ie` scaling + customEnv | `tbmq-ie.statefulSet.replicas=3`; `tbmq-ie.customEnv.TB_SERVICE_INTEGRATIONS_EXCLUDED=HTTP`; verify in-pod |
| L16 | Helm uninstall | post-L1: `helm uninstall`; verify chart-managed CMs / Secrets / Service / StatefulSets are gone; PVCs from `volumeClaimTemplates` survive (by design) and are reaped by `kubectl delete ns` |

### Phase 3 — Live PE license suite

PE overlay (`tbmq/values-pe.yaml`) plus the license-server JAVA_OPTS override applied
test-only on every install:

```bash
--set 'tbmq.customEnv.JAVA_OPTS=-Dtb.license.server=https://pe.tbqa.cloud:1443'
```

| ID | Scenario | Key overrides / actions |
|---|---|---|
| P1 | PE install with `license.existingSecret` | kubectl-pre-create `tbmq-license` Secret with the test key; `--set license.existingSecret=tbmq-license`; smoke + license-activated log + instance-data file present |
| P2 | PE install with inline `license.secret` | `--set license.secret=xGekoaiFH7MjFqxARJz9yKrc`; chart-managed `*-tbmq-license-secret` created; smoke + license activated |
| P3 | Pod-delete with PVC enabled | from P1, repeat `kubectl delete pod broker-0` 3 times in succession; capture instance-data file mtime + content hash before and after each delete; verify file is preserved across recreates; verify license re-validates without slot churn (broker logs) |
| P4 | Pod-delete with PVC **disabled** (regression) | install with `tbmq.persistence.enabled=false`; repeat the kill cycle; verify instance-data file is wiped each time and license shows fresh-instance behavior — confirms the PVC fix is meaningful |
| P5 | License rotation | (best effort — only one test key available) edit the `tbmq-license` Secret with `kubectl patch` to change a label so the underlying Secret content hash changes; verify `checksum/license-secret` annotation changes and broker rolls; broker comes back validated |
| P6 | PE without license value | install PE without setting either `license.secret` or `license.existingSecret`; verify broker fails to start; assert clear license-missing error in logs (expected behavior — not a defect) |

## 5. Phase 1 chart change — `tbmq.persistence` for `/data`

### Rationale

The PE license client writes a per-pod instance-data file to `/data/tbmq-instance-license-$(TB_SERVICE_ID).data`.
The license server logs each instance and counts toward the license slot pool. With
`emptyDir`, the file is destroyed on Pod recreation (rolling helm upgrade,
`kubectl delete pod`, node drain, eviction, scale up/down) — and the broker
re-registers as a fresh instance, churning license slots. The reference PE manifest
(`tbmq-pe-k8s`) already uses a `volumeClaimTemplate` for `/data`. The chart should match.

### Values surface

```yaml
tbmq:
  # Persistent storage for the broker /data directory. The PE license client writes
  # its per-pod instance-data file here, and the license server counts each fresh
  # instance against your license slot pool — so /data must survive Pod recreation
  # for PE deployments. CE deployments do not use /data for any persisted state, so
  # disabling persistence is safe for CE.
  persistence:
    # When true (default), /data is backed by a per-pod PVC created from a
    # StatefulSet volumeClaimTemplate. When false, /data is an emptyDir
    # (destroyed on Pod recreation).
    enabled: true
    # PVC size. 1Gi matches the official PE Kubernetes manifests.
    size: "1Gi"
    # StorageClass name. Empty means use the cluster's default StorageClass.
    storageClassName: ""
    # PVC access modes. ReadWriteOnce is correct for per-pod claims.
    accessModes: ["ReadWriteOnce"]
```

### Template change

In `tbmq/templates/tbmq/tbmq-statefulset.yaml`:

- When `tbmq.persistence.enabled=true`: omit the `tbmq-node-data` `emptyDir` volume
  entry and add a `volumeClaimTemplates` block with `metadata.name: tbmq-node-data`,
  `spec.accessModes`, `spec.resources.requests.storage`, and (if non-empty)
  `spec.storageClassName`.
- When `tbmq.persistence.enabled=false`: keep the existing `emptyDir` behavior.

The volume mount on the container stays at `/data` regardless.

### Scope of the change

- Broker StatefulSet only.
- IE StatefulSet, install Pod, pre-upgrade Job: unchanged — they stay on `emptyDir`.
  IE has no license; install/upgrade run once and don't need persistence.

### Doc updates (same commit)

- `tbmq/values.yaml` — new block with comments above (already shown).
- `tbmq/README.md` — add a "Persistence" section under "Configuration Reference"
  explaining the rationale, the values, and the CE-vs-PE recommendation.
  Update the "Uninstalling" section to note that `helm uninstall` does NOT delete
  PVCs created by `volumeClaimTemplates` — operators must reap them with
  `kubectl delete pvc -l ...` or `kubectl delete ns`.
- `tbmq/Chart.yaml` — `artifacthub.io/changes` entry: `kind: added — Optional PVC for the broker /data directory (tbmq.persistence) — required for PE so the license instance-data file survives Pod recreation.`
- `tbmq/docs/minikube/README.md` — note that the default storageClass on Minikube
  works out of the box; mention the PVC if the user inspects `kubectl get pvc`.

### Re-render of Phase 0

After the change lands, re-render Phase 0 cases that touch the broker StatefulSet
under both `tbmq.persistence.enabled=true` (default) and `tbmq.persistence.enabled=false`,
asserting on the `volumeClaimTemplates` block presence/absence and the `/data`
mount source.

## 6. Smoke test definition

Reused across every live scenario. Layered on top of each scenario's values overrides.

### Test-only overlay (every live scenario, never committed)

- `tbmq.customEnv.SECURITY_MQTT_BASIC_ENABLED=false` — disables MQTT basic auth so
  `mosquitto_pub` / `mosquitto_sub` can connect anonymously. The chart default
  `"true"` is a production-posture recommendation; testing it would require
  provisioning an MQTT client through the REST API as part of every scenario,
  which is outside the chart's surface.
- (PE only) `tbmq.customEnv.JAVA_OPTS=-Dtb.license.server=https://pe.tbqa.cloud:1443`
  — points the license client at the test license server.

### Setup

1. Wait `<release>-tbmq-node-*` Pods Ready (`kubectl wait --for=condition=Ready pod -l app=<release>-tbmq-node`).
2. Wait `<release>-tbmq-ie-*` Pods Ready.
3. If `installation.installDbSchema=true`: confirm `<release>-install-pod` reached `Succeeded`.
4. `kubectl port-forward svc/<release>-tbmq-node 1883:1883 8083:8083 -n <ns> &`;
   wait for both ports to accept connections (`nc -z localhost 1883 && nc -z localhost 8083`).

### Smoke checks

| ID | Check | Tool / command |
|---|---|---|
| S1 | QoS 0 round-trip | `mosquitto_sub -t t/qos0 -W 5 &`; `mosquitto_pub -t t/qos0 -m hello -q 0`; expect message within 5s |
| S2 | QoS 1 round-trip | same on `t/qos1` at QoS 1; PUBACK observed via `-d` |
| S3 | QoS 2 round-trip | same on `t/qos2` at QoS 2; PUBREC/PUBREL/PUBCOMP observed |
| S4 | Retained delivery | publish `t/retained=hello -r`; new subscribe receives immediately; cleanup with empty retained |
| S5 | Persistent session resume | client `smoke-A` connects with `clean-session=false`, subs `t/session` QoS 1, disconnects; another client publishes; `smoke-A` reconnects with `clean-session=false` and receives the queued message |
| S6 | HTTP UI reachable | `curl -fsSL http://localhost:8083/login` returns 200 with HTML |
| S7 | IE container healthy | all `<release>-tbmq-ie-*` containers report `ready=true` |
| S8 | DB schema present | `kubectl exec` into Postgres primary; `psql -c "SELECT count(*) FROM tb_schema_settings"` returns ≥ 1 with the right `schema_version` |

### PE-only checks (Phase 3)

| ID | Check |
|---|---|
| S9 | Broker logs contain `License activated` (or equivalent on success) within 60s of pod ready |
| S10 | `kubectl exec <broker-pod> -- ls -la /data/tbmq-instance-license-<pod-name>.data` succeeds |
| S11 (P3, P4) | Capture instance-data file mtime + content hash; `kubectl delete pod`; wait Ready; re-check — expected: same file (PVC enabled) or fresh file (PVC disabled) |

### Teardown

1. Kill port-forward.
2. `helm uninstall <release> -n <ns>`.
3. `kubectl delete ns <ns>` (also reaps PVCs from `volumeClaimTemplates`, which
   `helm uninstall` does not).

## 7. Execution operating procedure

### One-time bootstrap

```bash
minikube start --cpus=4 --memory=8192
minikube addons enable ingress
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  -n ingress-nginx --timeout=180s

helm install pgo oci://registry.developers.crunchydata.com/crunchydata/pgo \
  -n pgo --create-namespace
helm install strimzi strimzi/strimzi-kafka-operator \
  -n strimzi --create-namespace --version 0.50.0
helm repo add valkey https://valkey.io/valkey-helm/ && helm repo update
```

Operators stay up for the whole campaign.

### Per-scenario ritual

```bash
NS=tbmq-<scenario-id>
kubectl create namespace $NS

# Apply scenario's PostgresCluster / Kafka / Valkey manifests in $NS, wait Ready.
# (Same shape as docs/minikube/README.md, scoped to $NS.)

helm install my-tbmq tbmq/ -n $NS \
  -f docs/minikube/minikube-values.yaml \
  -f scenario-overlay.yaml \
  [-f tbmq/values-pe.yaml] \
  --set installation.installDbSchema=true

# Wait Ready. Run smoke. Capture logs on failure.

helm uninstall my-tbmq -n $NS
kubectl delete namespace $NS
```

### Defect-handling loop

1. **Capture** — pod logs (`--all-containers --previous` where appropriate),
   `kubectl describe`, `helm get manifest`, `helm get values`. Save under
   `verification-evidence/<scenario-id>/` (gitignored).
2. **Diagnose** — locate the defect in the chart sources.
3. **Fix** — edit chart; update `values.yaml` comments and README in the same
   commit if the defect changes user-facing behavior.
4. **Commit** — Conventional Commits, on `tbmq/2.3`. Reference the scenario that
   surfaced it. e.g. `fix(tbmq/L11): pre-upgrade Job missed FOO env when bar=true`.
5. **Re-render Phase 0** for any template the fix touched.
6. **Re-run** the failing scenario, plus every other scenario that touches the
   affected templates or values keys. The lookup is mechanical against the
   matrix tables above.
7. **Stop only when both the failing scenario and its adjacency set are green.**

### When to delete and recreate the cluster

Reuse the same minikube cluster by default. `minikube delete` only when a
scenario alters cluster-scope state in an irreversible way (e.g. broken operator
CRDs, ingress controller addon swap). I do not anticipate this in the planned
matrix; if it happens it is flagged before the destructive step.

## 8. Defect adjacency map

When fixing a defect, re-run the scenarios listed alongside the affected key.

| Affected template / values key | Re-run scenarios |
|---|---|
| `tbmq/templates/tbmq/tbmq-statefulset.yaml` | All Phase 0 broker rows; L1 / L3 / L9 / L11 / L12 / L13; all P* |
| `tbmq/templates/tbmq-ie/tbmq-ie-statefulset.yaml` | T11–T13, T15, T17; L1 / L15 |
| `tbmq/templates/install/post-install-job.yaml` | T19–T21; L1 (install Pod path) |
| `tbmq/templates/install/pre-upgrade-job.yaml` | T22–T25; L11 |
| `tbmq/templates/postgres/*` | T1–T3; L1 / L7 / L8 / L10 |
| `tbmq/templates/redis/*` | T4–T7; L1 |
| `tbmq/templates/kafka/*` | (any envFrom kafka usage) L1 / L15 |
| `tbmq/templates/license-secret.yaml`, `tbmq.license.*` helpers | T26–T31; P1–P5 |
| `tbmq/templates/regcred.yaml` | T32–T34; L14 |
| `tbmq/templates/loadbalancer/**` | T35–T39; L1 (nginx live) |
| `tbmq.persistence.*` (after Phase 1) | P3, P4 (regression); L12; rendered Phase 0 broker rows under both `enabled` states |

## 9. Deliverables

### Code commits on `tbmq/2.3`

- One commit for `tbmq.persistence` (Phase 1).
- One commit per defect found during Phases 0 / 2 / 3.
- Each commit: Conventional Commits message, single logical change, `values.yaml`
  comments + README + `Chart.yaml` changelog updated in the same commit when
  user-facing behavior changes. No squashing.

### `VERIFICATION_REPORT.md` at the repo root

Sections:

1. **Run summary** — date, chart version, app version, minikube/k8s/helm versions, single-line outcome.
2. **Scenario results table** — every Phase 0 / 2 / 3 scenario by ID, with `pass` / `fail-then-fixed-and-passed` / `n/a` / `deferred`. One-line reason for `n/a` and `deferred`.
3. **Defects found** — per defect: scenario(s) that surfaced it, root cause, commit(s) that fixed it, scenarios re-run after fix.
4. **Chart change: `tbmq.persistence`** — rationale, commit ref, doc updates, observed PVC reuse on pod recreation.
5. **Documentation updates** — every README / values.yaml / minikube-doc edit mapped to the commit that landed it.
6. **Out-of-scope items deferred** — ArgoCD live, cloud LB live, real cross-version upgrade, chart 1.x → 2.0.0, TLS/mTLS/SASL/Kafka-auth/Postgres-TLS, WebSocket, NodePort/PDB/SA/RBAC chart-feature gaps. One-line reason each.
7. **Smoke-test deviation note** — `SECURITY_MQTT_BASIC_ENABLED=false` overlay on every live scenario, and the test license-server `JAVA_OPTS` override on PE scenarios. Both are test-only and not committed.

No new files outside the chart and the report. Evidence captured during execution
lives under `verification-evidence/`, which is added to `.gitignore` if not already.

## 10. Open items / risks

- **License-server rate limits or IP pinning.** The test license server may rate-limit
  or refuse connections. If P1 fails before reaching Smoke, I'll escalate to Dima
  before retrying.
- **License rotation (P5) is best-effort.** Only one test license key is available,
  so rotation is simulated by mutating the Secret in a way that changes the content
  hash without changing the license value. If even that fails to trigger a roll,
  P5 is downgraded to "verify checksum/license-secret annotation matches the
  Secret's content hash on every render" (Phase 0 assertion only) and noted as
  partially deferred in the report.
- **PVC reaping on namespace deletion.** Some StorageClass / PV configurations leave
  orphan PVs after PVC deletion. If observed on Minikube's default storage
  provisioner, flag in the report and add a manual cleanup step to the per-scenario
  ritual.
- **Minikube ingress-controller addon stability across many helm install/uninstall
  cycles.** If the ingress controller misbehaves, fall back to disabling it for
  scenarios that don't need it.
