#---
#▲ [Back to Main Hub](../../README.md) | 📊 [Monitoring Overview](./README.md) | Next: [Dashboards & Latency Tools](./dashboards-latencyerrors.md) ▶
#---
# Prometheus Installation & Exporter Configuration

## 1. How Prometheus Collects Metrics
Prometheus is a **pull-based time-series engine**, not a log parser. It periodically sends HTTP `GET` requests (`scrapes`) to target endpoints (e.g., `http://<host>:9100/metrics`) that expose plain-text metrics in the OpenMetrics format.

* **Infrastructure Metrics:** Collected by deploying **Exporters** (such as `node_exporter` for OS/hardware or `kube-state-metrics` for Kubernetes objects).
* **Application Metrics:** Exposed directly by importing a Prometheus client library (Go, Python, Java, Node.js) into application code.

### Discovering Scraped Metric Names
* **Inspect Target Endpoint:** Run `curl http://<target-ip>:<port>/metrics` to view all exposed metric names, `# HELP` descriptions, and `# TYPE` definitions.
* **Prometheus UI:** Open `:9090/graph` and use the **Metrics Explorer** autocomplete next to the query input.
* **Query the API:**
  ```bash
  curl -s http://localhost:9090/api/v1/label/__name__/values | jq
  ```

#---

## 2. Standalone Linux / EC2 Installation

Just like a Splunk Forwarder, every standalone Linux VM or EC2 instance requires `node_exporter` installed to expose CPU, memory, disk, and network metrics.

### Step A: Install Prometheus Server
```bash
sudo groupadd --system prometheus
sudo useradd -s /sbin/nologin --system -g prometheus prometheus
sudo mkdir -p /etc/prometheus /var/lib/prometheus

wget https://github.com
tar xvfz prometheus-2.54.0.linux-amd64.tar.gz
cd prometheus-2.54.0.linux-amd64

sudo cp prometheus promtool /usr/local/bin/
sudo cp -r consoles console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
```

Create `/etc/prometheus/prometheus.yml`:
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'linux_nodes'
    static_configs:
      - targets: ['<VM_IP_1>:9100', '<VM_IP_2>:9100']
```

Create `/etc/systemd/system/prometheus.service` and start it:
```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090
Restart=always

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
```

### Step B: Install `node_exporter` on Target Linux VMs
```bash
wget https://github.com
tar xvfz node_exporter-1.8.2.linux-amd64.tar.gz
sudo cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter

cat <<EOF | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

#---

## 3. Kubernetes Installation (GKE vs. On-Prem RKE2)

On Kubernetes, Prometheus runs on worker nodes via the `kube-prometheus-stack` Helm chart. It automatically deploys `node-exporter` as a **DaemonSet** (one pod per node) and `kube-state-metrics`.

### GKE Values (`values-gke.yaml`)
Google manages the GKE control plane (`etcd`, `kube-scheduler`, `kube-controller-manager`), so disable scraping those targets to avoid false alerts:
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard-rwo
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
```

### On-Prem RKE2 Override (`values-rke2.yaml`)
In RKE2, you own the control plane nodes. Enable control plane monitoring:
```yaml
kubeEtcd:
  enabled: true
  service:
    enabled: true
    port: 2379
    targetPort: 2379
kubeControllerManager:
  enabled: true
kubeScheduler:
  enabled: true
```

### Deploy via Helm
```bash
helm repo add prometheus-community https://github.io
helm repo update

helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values-gke.yaml
```

### Dynamic Application Scraping (`ServiceMonitor`)
Instead of editing static IPs, create a `ServiceMonitor` CRD that matches your application's Kubernetes `Service` labels:
```yaml
apiVersion: ://coreos.com
kind: ServiceMonitor
metadata:
  name: payment-service-monitor
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
      - production
  selector:
    matchLabels:
      app: payment-service
  endpoints:
    - port: http-metrics
      path: /metrics
      interval: 15s
```
