# Terraform Production Readiness Guide

A standardized operational playbook for structuring, securing, automating, and troubleshooting Infrastructure as Code (IaC) with Terraform across multi-cloud environments.

---

## Table of Contents
1. [Repository & Module Structure](#1-repository--module-structure)
2. [File & Template Functions (`file` vs. `templatefile`)](#2-file--template-functions-file-vs-templatefile)
3. [Remote State & Locking](#3-remote-state--locking)
4. [CI/CD Automation with GitHub Actions (OIDC)](#4-cicd-automation-with-github-actions-oidc)
5. [Drift Detection & Remediation](#5-drift-detection--remediation)
6. [Importing Existing Infrastructure](#6-importing-existing-infrastructure)
7. [Recovering from Partial Applies](#7-recovering-from-partial-applies)
8. [Troubleshooting & Runbook](#8-troubleshooting--runbook)

---

## 1. Repository & Module Structure

Separate **reusable modules** (blueprints with no provider/backend blocks) from **live environment directories** (callers with isolated remote state files).

```text
infrastructure-repo/
├── modules/                                  # Reusable blueprints
│   └── gcp-workload-identity/
│       ├── main.tf                           # Core resources
│       ├── variables.tf                      # Input contract with validation blocks
│       ├── outputs.tf                        # Exported attributes
│       └── README.md                         # Auto-generated via terraform-docs
│
└── environments/                             # Isolated state per environment
    ├── dev/
    │   ├── main.tf
    │   ├── providers.tf
    │   └── terraform.tfvars
    └── prod/
        ├── main.tf
        ├── providers.tf
        └── terraform.tfvars
```

### Module Design Standards
* **No Provider or Backend Blocks in Modules:** Child modules must inherit providers from the calling environment so they remain composable.
* **Pin Module Versions:** When referencing external Git modules, always pin to an immutable Git tag (`?ref=v1.0.0`), never `?ref=main`.
* **Input Validation:** Use `validation` blocks inside `variables.tf` to enforce naming conventions and allowed environments (`dev`, `staging`, `prod`) during `terraform plan`.
* **Cross-Platform Lockfile:** Commit `.terraform.lock.hcl` with hashes for both local development and CI runners:
  ```bash
  terraform providers lock \
    -platform=linux_amd64 \
    -platform=darwin_arm64
  ```

---

## 2. File & Template Functions (`file` vs. `templatefile`)

Always anchor file paths with **`${path.module}`** so Terraform resolves paths relative to the module directory regardless of where the CLI is invoked.

| Function | Syntax | Use Case |
| :--- | :--- | :--- |
| **`file()`** | `file("${path.module}/policies/deny.json")` | Static files requiring no variable substitution. |
| **`templatefile()`** | `templatefile("${path.module}/init.sh.tftpl", { env = var.env })` | Dynamic IAM policies or VM startup scripts using `${var}` and `%{ for ... }` loops. *(Escape bash `$VAR` with `$$VAR` inside `.tftpl` files.)* |

---

## 3. Remote State & Locking

Never store `terraform.tfstate` locally or commit it to Git. Configure an encrypted remote backend with **object versioning** (for disaster recovery) and **state locking** (to prevent concurrent state corruption).

### Google Cloud Storage (GCS)
```hcl
terraform {
  required_version = ">= 1.5.0"

  backend "gcs" {
    bucket = "YOUR_PROJECT_ID-tfstate"
    prefix = "environments/prod"
  }
}
```

### Amazon Web Services (S3 Native Locking — Terraform v1.10+)
```hcl
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "my-company-prod-tfstate"
    key          = "environments/prod/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

### Microsoft Azure (Blob Storage)
```hcl
terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "mycompanytfstate01"
    container_name       = "tfstate"
    key                  = "environments/prod/terraform.tfstate"
  }
}
```

### Migrating Existing Local State
```bash
terraform init -migrate-state
# Confirm with 'yes', verify remote state exists, then remove local .tfstate files
```

---

## 4. CI/CD Automation with GitHub Actions (OIDC)

Enforce separation of duties using two distinct identities via keyless OpenID Connect (OIDC) federation (see [CI/CD OIDC Federation](cicd-oidc-federation.md) and [Service Accounts & Workload Identity](../05-security-iam/README.md)):
1. **PR Plan Identity (Read-Only):** Granted viewer permissions to run `terraform plan` on Pull Requests.
2. **Apply Identity (Read/Write):** Restricted exclusively to `main` branch merges gated by a **GitHub Environment** (`production`) requiring manual reviewer approval.

### Pull Request Plan Workflow (`.github/workflows/terraform-plan.yml`)
```yaml
name: Terraform Plan on PR

on:
  pull_request:
    branches: [main]
    paths: ['environments/**', 'modules/**']

permissions:
  contents: read
  id-token: write
  pull-requests: write

env:
  TF_VERSION: "1.10.5"
  WORKING_DIR: "environments/prod"

jobs:
  plan:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate via OIDC (Read-Only SA)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_TERRAFORM_PLAN_SA_EMAIL }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Format & Validate
        run: |
          terraform fmt -check -recursive
          terraform init -input=false
          terraform validate -no-color

      - name: Plan
        id: plan
        run: terraform plan -no-color -input=false -out=tfplan
        continue-on-error: true

      - name: Comment Plan on PR
        uses: actions/github-script@v7
        env:
          PLAN: "${{ steps.plan.outputs.stdout }}"
        with:
          script: |
            const truncatedPlan = process.env.PLAN.substring(0, 60000);
            const output = `#### Terraform Plan 📖 \`${{ steps.plan.outcome }}\`
            <details><summary>Show Plan Output</summary>\n\n\`\`\`hcl\n${truncatedPlan}\n\`\`\`\n</details>`;
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });
            const botComment = comments.find(c => c.user.type === 'Bot' && c.body.includes('#### Terraform Plan 📖'));
            if (botComment) {
              await github.rest.issues.updateComment({ owner: context.repo.owner, repo: context.repo.repo, comment_id: botComment.id, body: output });
            } else {
              await github.rest.issues.createComment({ owner: context.repo.owner, repo: context.repo.repo, issue_number: context.issue.number, body: output });
            }

      - name: Fail if Plan Failed
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

### Protected Merge Apply Workflow (`.github/workflows/terraform-apply.yml`)
```yaml
name: Terraform Apply on Merge

on:
  push:
    branches: [main]
    paths: ['environments/**', 'modules/**']

permissions:
  contents: read
  id-token: write

concurrency:
  group: terraform-apply-prod
  cancel-in-progress: false # Never cancel an active apply

env:
  TF_VERSION: "1.10.5"
  WORKING_DIR: "environments/prod"

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate via OIDC (Write SA)
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_TERRAFORM_APPLY_SA_EMAIL }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Init, Plan & Apply
        run: |
          terraform init -input=false
          terraform plan -no-color -input=false -out=tfplan
          terraform apply -auto-approve -input=false tfplan
```

---

## 5. Drift Detection & Remediation

Schedule a daily read-only pipeline (`cron: '0 2 * * *'`) using **`terraform plan -detailed-exitcode`** to catch manual console changes:
* **Exit Code `0`:** No drift detected.
* **Exit Code `1`:** Execution/authentication error.
* **Exit Code `2`:** **Drift detected** (live state differs from Git).

**Remediation Rules:**
* **Unauthorized manual change:** Run `terraform apply` to restore the desired state in Git.
* **Approved emergency hotfix:** Backport the change into `.tf` files and verify `terraform plan` returns `No changes`.

---

## 6. Importing Existing Infrastructure

Use declarative **`import` blocks** (Terraform v1.5+) to adopt existing cloud resources into state without recreating them:

```hcl
# 1. Declare the import block in imports.tf
import {
  to = google_storage_bucket.existing_logs
  id = "my-company-prod-legacy-logs"
}
```

```bash
# 2. Generate matching HCL configuration automatically
terraform plan -generate-config-out=generated_resources.tf

```

```
# 3. Review & clean up generated_resources.tf, move into main.tf, and apply

terraform apply

# 4. Remove the temporary import block once recorded in state
```

---

## 7. Recovering from Partial Applies

Terraform writes to the remote state file after each individual resource finishes, not only at the end of a run.
If terraform apply fails halfway through:
1. Do NOT delete terraform.tfstate or manually delete resources that already succeeded.
2. Fix the root cause of the failing resource (e.g., IAM permission, quota limit, or naming conflict).
3. Re-run terraform apply: Terraform skips completed resources and resumes from the failed resource.
4. If a single resource was left in a broken state, force a clean recreation of only that resource:
   bash terraform apply -replace="RESOURCE_TYPE.RESOURCE_NAME"

---


## 8. Troubleshooting & Runbook

| Symptom / Error | Root Cause | Resolution |
| :--- | :--- | :--- |
| `Error acquiring the state lock` | Active CI run in progress, or a crashed runner left a stale lock behind. | Verify no CI apply job is running, then run `terraform force-unlock <LOCK_ID>` using the ID from the error output. |
| `Resource already exists (409)` | Resource exists in the cloud, but is missing from `terraform.tfstate`. | Add an `import` block for the resource ID and run `terraform apply` to adopt it into state. |
| Renaming a resource triggers destroy/recreate | Terraform treats a renamed resource block as a brand-new resource. | Add a `moved` block (`moved { from = old_addr to = new_addr }`) to remap the state address in-place. |
| Provider checksum mismatch in CI | `.terraform.lock.hcl` lacks `linux_amd64` hashes for Linux CI runners. | Run `terraform providers lock -platform=linux_amd64` locally and commit the updated lockfile. |
| Opaque Cloud API `400` or `403` error | Standard Terraform CLI output hides low-level HTTP request/response details. | Run `TF_LOG=DEBUG TF_LOG_PATH=./tf-debug.log terraform plan` locally to inspect API traces (do not commit the log file). |


