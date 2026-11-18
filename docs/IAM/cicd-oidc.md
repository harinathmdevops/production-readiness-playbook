## 7. CI/CD OIDC Federation (Zero-Secret Pipelines)

Instead of storing long-lived cloud credentials in CI/CD repository secrets, configure OpenID Connect (OIDC) trust relationships so pipelines exchange short-lived tokens at runtime.

### GitHub Actions -> AWS (IAM Role)

1. **Create the OIDC Identity Provider in AWS (One-time setup per account):**
```bash
aws iam create-open-id-connect-provider \
    --url https://githubusercontent.com \
    --client-id-list ://amazonaws.com
```

2. **Create a Trust Policy locked to a specific repository and branch (`trust-github.json`):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/://githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "://githubusercontent.com:aud": "://amazonaws.com",
          "://githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

3. **Workflow Snippet (`.github/workflows/deploy.yml`):**
```yaml
permissions:
  id-token: write   # Required to request the OIDC JWT
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS Credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-actions-deploy-role
          aws-region: us-east-1
      - name: Verify Identity
        run: aws sts get-caller-identity
```

---

### GitHub Actions -> Google Cloud (Workload Identity Federation)

1. **Create Pool, OIDC Provider, and IAM Binding:**
```bash
# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
    --location="global" \
    --display-name="GitHub Actions Pool"

# Create OIDC Provider restricted to your GitHub organization
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --display-name="GitHub Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository_owner == 'YOUR_ORG'" \
    --issuer-uri="https://githubusercontent.com"

# Allow the specific repository to impersonate the GCP Service Account
gcloud iam service-accounts add-iam-policy-binding "deploy-sa@PROJECT_://gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://://googleapis.com"
```

2. **Workflow Snippet (`.github/workflows/deploy.yml`):**
```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
          service_account: "deploy-sa@PROJECT_://gserviceaccount.com"
      - name: Verify Identity
        run: gcloud auth list
```

---

### GitLab CI -> Microsoft Azure (Federated Credential)

1. **Add a Federated Credential to a User-Assigned Managed Identity:**
```bash
az identity federated-credential create \
    --name "gitlab-main-branch" \
    --identity-name "app-backend-identity" \
    --resource-group "YOUR_RESOURCE_GROUP" \
    --issuer "https://gitlab.com" \
    --subject "project_path:YOUR_GROUP/YOUR_PROJECT:ref_type:branch:ref:main" \
    --audiences "https://gitlab.com"
```

2. **Pipeline Snippet (`.gitlab-ci.yml`):**
```yaml
deploy_azure:
  image: ://microsoft.com
  id_tokens:
    AZURE_ID_TOKEN:
      aud: https://gitlab.com
  script:
    - az login --service-principal -u "\$AZURE_CLIENT_ID" -t "\(AZURE_TENANT_ID" --federated-token "\)AZURE_ID_TOKEN"
    - az account show
```
