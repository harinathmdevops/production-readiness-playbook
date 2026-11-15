# Multi-Cluster Architecture, Cost Optimization & Alerting (135 GKE + 4 RKE2)

## 1. Hub-and-Spoke Topology

Running standalone stateful Prometheus databases across **135 GKE clusters (Primary + DR)** and **4 On-Prem RKE2 clusters (2 Primary + 2 DR)** creates high storage overhead and fragmented dashboards.

Instead, deploy lightweight **Prometheus Agents** (or Grafana Alloy) at the edge and stream metrics via `remote_write` to a central storage cluster hosted in your primary GCP region:

```text
[135 GKE Clusters] ──(Prometheus Agent + Sharding)──┐
                                                    ├──► [Central VictoriaMetrics Cluster] ──► [Central Grafana]
[4 RKE2 Clusters]  ──(Prometheus Agent via VPN)─────┘
```

### Why VictoriaMetrics Over Thanos / Mimir?
While Thanos and Grafana Mimir are active CNCF/Grafana projects, **VictoriaMetrics Cluster** (`vminsert`, `vmstorage`, `vmselect`) provides the lowest total cost of ownership for ~140 clusters:
* **3x–5x lower RAM** and **~1.7x lower CPU** footprint than Grafana Mimir.
* **Up to 10x better compression** on block/object storage.
* Native drop-in support for Prometheus `remote_write` and PromQL queries.

#---

## 2. Edge Sharding & Remote Write Configuration

For large clusters, enable horizontal sharding in `kube-prometheus-stack`. The Prometheus Operator automatically splits scrape targets across pods using `hashmod` relabeling:

```yaml
prometheus:
  prometheusSpec:
    mode: Agent
    shards: 2 # Splits scrape load evenly across 2 Agent pods
    externalLabels:
      cluster: "gke-prod-us-central1-01" # Unique per cluster via ArgoCD ApplicationSet
      environment: "production"
      platform: "gke" # or "rke2"
    remoteWrite:
      - url: "https://company.com"
        queueConfig:
          capacity: 10000
          maxShards: 50
          maxSamplesPerSend: 2000
```

#---

## 3. Bandwidth & Storage Cost Reduction Tactics

Streaming raw metrics from 139 clusters incurs GCP egress and storage costs unless filtered at the edge:

1. **Co-Locate Central Storage:** Host VictoriaMetrics in the same GCP region as the majority of your GKE clusters to eliminate cross-region GCP network egress fees.
2. **Tier Scrape Intervals by Environment:**
   * **Production (Primary):** `15s`–`30s`
   * **DR & Non-Production GKE:** `60s` (reduces bandwidth and storage volume by 50–75%).
3. **Drop High-Cardinality / Unused Metrics at the Edge:** Use `metricRelabelings` in your `ServiceMonitor` to drop noisy container or Go runtime metrics before they enter `remote_write`:
   ```yaml
   metricRelabelings:
     - sourceLabels: [__name__]
       regex: "container_tasks_state|container_memory_failures_total|go_gc_.*"
       action: drop
   ```

#---

## 4. Production `PrometheusRule` Library

```yaml
apiVersion: ://coreos.com
kind: PrometheusRule
metadata:
  name: enterprise-k8s-alerts
  namespace: monitoring
spec:
  groups:
    - name: node-health
      rules:
        - alert: NodeNotReady
          expr: kube_node_status_condition{condition="Ready",status="true"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Node {{ labels.node in labels.cluster }} is NotReady"

        - alert: NodeHighMemoryUsage
          expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Node {{ \$labels.instance }} memory usage above 85%"

        - alert: NodeDiskPressureSoon
          expr: predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[6h], 24 * 3600) < 0
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "Disk on {{ \$labels.instance }} will fill within 24 hours"

    - name: workload-health
      rules:
        - alert: PodOOMKilled
          expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "Container {{ \$labels.container }} in {{ labels.namespace / labels.pod }} was OOMKilled"

        - alert: HighCPUThrottling
          expr: |
            sum by (cluster, namespace, pod) (rate(container_cpu_cfs_throttled_periods_total[5m]))
            /
            sum by (cluster, namespace, pod) (rate(container_cpu_cfs_periods_total[5m])) > 0.25
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ labels.namespace / labels.pod }} is CPU throttled > 25%"

    - name: storage-and-pipeline
      rules:
        - alert: PersistentVolumeFillingUp
          expr: (kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) * 100 < 15
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "PVC {{ labels.namespace / labels.persistentvolumeclaim }} has < 15% free space"

        - alert: PrometheusRemoteWriteLagging
          expr: (prometheus_remote_storage_highest_timestamp_in_seconds - prometheus_remote_storage_queue_highest_sent_timestamp_seconds) > 120
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Cluster {{ \$labels.cluster }} remote_write is lagging > 2 minutes"
```
