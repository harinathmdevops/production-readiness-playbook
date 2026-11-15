# Observability & Monitoring Playbook

This module provides an end-to-end engineering guide for implementing metrics, alerting, and dashboards across standalone Linux VMs, Google Kubernetes Engine (GKE), and On-Premises RKE2 clusters.

## Learning & Implementation Roadmap

1. **[Prometheus Installation & Exporters](./prometheus-installation.md)**
   * Pull-based metrics fundamentals (Metrics vs. Logs).
   * Discovering scraped metric names and metadata.
   * Standalone Linux / EC2 installation (`prometheus` & `node_exporter`).
   * Kubernetes installation via `kube-prometheus-stack` (GKE vs. RKE2 differences) and `ServiceMonitor` CRDs.
2. **[PromQL & Grafana Dashboards (RED/USE)](./dashboards-latency-errors.md)**
   * Metric types (Counter, Gauge, Histogram) and core PromQL operators.
   * Designing Latency, Error, and Saturation dashboards using the RED and USE methods.
   * Grafana dynamic variables and community dashboard IDs.
3. **[Logs vs. Metrics & Unified Correlation](./log-infra-correlation.md)**
   * Why Prometheus does not parse logs directly.
   * **Prometheus Agent Mode** vs. **Grafana Alloy** (unified metrics, logs, and traces).
   * Correlating infrastructure metrics with application logs in Grafana.
4. **[Multi-Cluster Architecture, Cost Optimization & Alerting](./multi-cluster-alerting-architecture.md)** *(New File)*
   * Hub-and-spoke architecture for **135 GKE + 4 RKE2** clusters.
   * Horizontal sharding, **VictoriaMetrics** vs. Mimir/Thanos cost comparison, and cardinality reduction.
   * Production `PrometheusRule` library and Alertmanager routing.

