## IAM & Service Account Security Review Checklist

Please complete all items below before requesting approval for any changes involving service accounts, IAM roles, managed identities, or Kubernetes RBAC.

### 1. Identity Hygiene & Lifecycle
- [ ] **Dedicated Identity:** This workload uses its own dedicated service account/role and does not share credentials with another service or environment (`dev`/`staging`/`prod` are isolated).
- [ ] **Naming Convention:** The identity follows `<workload-name>-<env>-<sa|role|id>` naming standards and includes owner/team tags.
- [ ] **No Static Credentials:** No JSON key files, static AWS access keys, client secrets, or long-lived Kubernetes tokens are generated, committed, or stored in CI/CD secrets.
- [ ] **Workload Identity / OIDC:** Authentication uses native Workload Identity, IAM Roles, Managed Identities, gMSA, or OIDC federation.

### 2. Least-Privilege Access
- [ ] **No Wildcard Permissions:** Policies avoid `"Action": "*"` or `"Resource": "*"` unless explicitly required by the cloud API and documented below.
- [ ] **No Broad Admin Roles:** High-privilege roles (`Owner`, `Editor`, `AdministratorAccess`, `Contributor`, `cluster-admin`) are not assigned to application workloads.
- [ ] **Resource-Level Scoping:** Permissions are scoped to specific buckets, tables, queues, KMS keys, or Kubernetes namespaces rather than entire accounts or subscriptions.

### 3. Trust Boundaries & Federation
- [ ] **Strict OIDC Conditions:** Any federated trust policy restricts `sub` (subject) to a specific repository, branch, or environment rather than an entire GitHub/GitLab organization.
- [ ] **Kubernetes Token Mounting:** `automountServiceAccountToken: false` is set on Pod specs that do not interact with the Kubernetes API.

### Justification for Elevated Permissions (If Applicable)
> *Briefly explain why any broad read/write permission or cross-account trust is required:*
