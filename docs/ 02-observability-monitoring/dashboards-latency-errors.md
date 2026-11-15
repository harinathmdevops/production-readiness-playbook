# PromQL & Grafana Dashboards (Latency, Errors & Saturation)

## 1. Metric Types & PromQL Operators

| Metric Type | Behavior | Primary PromQL Functions |
| :--- | :--- | :--- |
| **Counter** | Monotonically increasing value (resets to `0` on restart). | `rate()`, `increase()` |
| **Gauge** | Point-in-time snapshot that goes up or down. | `avg_over_time()`, `min()`, `max()` |
| **Histogram** | Counts observations into configurable `le` buckets. | `histogram_quantile()` |

### Essential PromQL Queries
* **Request Rate (RPS):** Always use `rate()` over a window at least 4x your scrape interval:
  ```promql
  sum by (service) (rate(http_requests_total{namespace="production"}[5m]))
  ```
* **HTTP 5xx Error Rate (%):**
  ```promql
  sum(rate(http_requests_total{status=~"5.."}[5m])) 
  / 
  sum(rate(http_requests_total[5m])) * 100
  ```
* **p95 Latency (Histograms):** Aggregate `le` buckets before calculating the quantile:
  ```promql
  histogram_quantile(0.95, sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))
  ```
* **Top 5 CPU-Consuming Pods:**
  ```promql
  topk(5, sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="production"}[5m])))
  ```

#---

## 2. Dashboard Design Frameworks

### The RED Method (Microservices & APIs)
Every service dashboard should display three core panels:
1. **Rate:** Requests per second (`http_requests_total`).
2. **Errors:** Percentage of failed requests (`status=~"5.."`).
3. **Duration:** Latency percentiles (`p50`, `p95`, `p99`).

### The USE Method (Nodes, Cloud Infra & Storage)
Every infrastructure dashboard should track:
1. **Utilization:** % of resource busy (CPU %, Memory %, PVC disk %).
2. **Saturation:** Queue depth or throttling (`container_cpu_cfs_throttled_periods_total`).
3. **Errors:** OOMKills (`kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`) or network packet drops.

#---

## 3. Grafana Best Practices & Dashboard IDs

* **Dynamic Variables:** Define `$cluster`, `$namespace`, and `$pod` variables at the dashboard top using `label_values(kube_pod_info, namespace)` so one dashboard works across all environments.
* **Adaptive Intervals:** Use `[$__rate_interval]` instead of hardcoded `[5m]` in Grafana panels so charts render accurately across both 15-minute and 30-day zoom ranges.
* **Pre-Built Community Dashboards (Import via ID):**
  * **`1860`:** Node Exporter Full (Linux VM / K8s Worker Node hardware metrics).
  * **`15757`:** Kubernetes / Views / Global (Multi-cluster overview).
  * **`15760`:** Kubernetes / Views / Pods (Pod CPU, memory, throttling, and network).

