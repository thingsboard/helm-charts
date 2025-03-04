# TBMQ Helm Chart (Pre-Release)

🚀 ThingsBoard MQTT Broker (TBMQ) Helm Chart for deploying a scalable, high-performance MQTT broker on Kubernetes.

⚠️ This is a pre-release version. More documentation and features will be added in future updates.

📖 Documentation & Resources:

 - 🔗 TBMQ [Documentation](https://thingsboard.io/products/mqtt-broker/)
 - 💻 GitHub [Repository](github.com/thingsboard/tbmq)

## Quick Install Guide

### 1. Build Helm Dependencies

Before installing, ensure dependencies are built:

```shell
helm dependency build
```

### 2. Install TBMQ

```shell
helm install tbmq ./ --set installation.installTBMQ=true --namespace tbmq --create-namespace --debug
```

### 3. Set Kubernetes Context

```shell
kubectl config set-context --current --namespace=tbmq
```

### 4. Upgrade TBMQ

For the first upgrade, run:

```shell
helm upgrade tbmq ./ --namespace tbmq --reset-values
```

> **Note:** This resets what was previously set using --set during installation.

For subsequent upgrades, simply run:

```shell
helm upgrade tbmq ./ --namespace tbmq
```
