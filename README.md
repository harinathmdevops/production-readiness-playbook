# 🚀 Production Readiness & Cloud Native Playbook

Welcome to the **Production Readiness Playbook**. This repository serves as a highly structured, battle-tested engineering guide for cloud architects, DevOps engineers, and systems administrators. It covers everything from cross-border data migrations to cloud-native cluster bootstrap strategies and full-stack observability.

---

## 🗺️ Playbook Navigation Hub

Click on any section below to navigate to the respective implementation guides. Every submodule contains deep-dive architecture designs, configuration scripts, and post-deployment checklists.

### 🗄️ [1. Enterprise Database Migrations](./docs/01-database-migrations/README.md)
*   [Cross-Region Swiss (Prod) to German (Non-Prod) MariaDB Migration](./docs/01-database-migrations/ch-de-mariadb-migration.md) — Secure multi-threaded logical replication, inline PII data masking, and network isolation configurations.

### 📊 [2. Full-Stack Observability & Monitoring](./docs/02-observability-monitoring/README.md)
*   [Prometheus Core Engine Setup](./docs/02-observability-monitoring/prometheus-installation.md) — Installation blueprints, defining application custom metrics, and tuning scrape configurations.
*   [Mitigating Latency & Error Spikes](./docs/02-observability-monitoring/dashboards-latency-errors.md) — Constructing production Grafana dashboards using RED/USE frameworks to capture downstream anomalies.
*   [Log Correlation & Blast Radius Triaging](./docs/02-observability-monitoring/log-infra-correlation.md) — Connecting infrastructure resource exhaustion metrics directly to application trace logs to calculate incident blast radius.

### ☁️ [3. Multi-Cloud Architecture & Managed Kubernetes](./docs/03-cloud-architecture-k8s/README.md)
*   [Cloud Provider Matrix Comparison](./docs/03-cloud-architecture-k8s/cloud-provider-comparison.md) — A direct, feature-by-feature trade-off evaluation across AWS, Microsoft Azure, and Google Cloud Platform.
*   [Enterprise Landing Zone Blueprints](./docs/03-cloud-architecture-k8s/landing-zone-blueprints.md) — Designing structural multi-account organizational units (OUs), security guards, and identity boundaries.
*   [Production Kubernetes from Scratch](./docs/03-cloud-architecture-k8s/kubernetes-from-scratch.md) — Architectural prerequisites and day-1 setup policies for **AWS EKS**, **Azure AKS**, and **Google GKE**.

### ⚙️ [4. Continuous Integration & Deployment (CI/CD)](./docs/04-devops-cicd/README.md)
*   [Unified Pipeline Prerequisites Blueprint](./docs/04-devops-cicd/pipeline-prerequisites.md) — Core requirements, runner configurations, and secret handling across **Jenkins**, **GitLab CI/CD**, and **GitHub Actions**.

---

## 🛠️ Repository Global Philosophy

1. **Security First:** All templates mandate network private-endpoints, encryption-at-rest, and explicit least-privilege configurations.
2. **Infrastructure as Code (IaC):** Blueprints are structured to be easily mapped directly into Terraform, OpenTofu, or Pulumi modules.
3. **Zero Raw PII:** Non-production environments must be paired with anonymization strategies to guarantee compliance with EU GDPR and Swiss FADP regulations.

---
*Maintained by the Cloud Native Engineering Community. For architectural corrections or contributions, please open a Pull Request.*
