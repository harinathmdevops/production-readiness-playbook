# Log-to-Metric Pipelines & Unified Telemetry (Grafana Alloy)

## 1. Logs vs. Metrics in Prometheus
* **Prometheus does NOT scrape log files.** If you point Prometheus at a log endpoint, scraping fails.
* **Turning Logs into Metrics:** If an application cannot be instrumented with a Prometheus client library, deploy a log collector (**Grafana Alloy** or **Vector**) to tail container logs, match regex patterns (e.g., `ERROR` or HTTP `500`), increment a counter, and expose `/metrics` for Prometheus to scrape.

#---

## 2. Prometheus Agent Mode vs. Grafana Alloy

Both tools run as lightweight edge collectors with zero long-term local TSDB storage, forwarding data via `remote_write` to a central backend. However, they are distinct installations:

| Dimension | Prometheus Agent Mode | Grafana Alloy (Successor to Grafana Agent) |
| :--- | :--- | :--- |
| **Binary / Chart** | Standard `prometheus` binary (`mode: Agent` in `kube-prometheus-stack`). | Separate `grafana/alloy` binary and Helm chart (OpenTelemetry-based). |
| **Signals Collected** | **Metrics only**. | **Unified:** Metrics + Logs + Traces + Continuous Profiling. |
| **Built-in Exporters** | None (requires separate `node_exporter` DaemonSet). | **Built-in `node_exporter`** (`prometheus.exporter.unix`) inside the same agent. |
| **Configuration** | Standard YAML (`prometheus.yml` / `ServiceMonitor`). | Component-based HCL syntax (`config.alloy`). |
| **Recommended Use** | Pure metrics environments already standardized on Prometheus Operator CRDs. | Unified observability teams consolidating metrics (VictoriaMetrics/Mimir) and logs (Loki) into one DaemonSet. |

*(Note: Legacy **Grafana Agent** and **Promtail** are deprecated/EOL; standardize new deployments on **Grafana Alloy** or **Prometheus Agent Mode**).*

#---

## 3. Correlating Infrastructure Metrics with Logs in Grafana

When a dashboard shows a CPU spike or HTTP 5xx surge, engineers should pivot directly to the exact container logs without leaving Grafana:

1. **Standardize Labels:** Ensure both your metrics (`ServiceMonitor`) and logs (`Alloy` / `Loki`) attach identical Kubernetes metadata labels: `cluster`, `namespace`, `pod`, and `container`.
2. **Configure Derived Fields / Data Source Links:** In Grafana's Prometheus data source settings, link metric labels (`cluster`, `namespace`, `pod`) to a Loki explore query:
   ```logql
   {cluster="\$__data.fields.cluster", namespace="\(__data.fields.namespace", pod="\)__data.fields.pod"} |= "error"
   ```
3. **Split-Screen Triage:** Use Grafana's **Explore → Split View** with Prometheus metrics on the left and Loki logs on the right synced to the exact same time window.

