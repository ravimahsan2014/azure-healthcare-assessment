# Azure Healthcare Application — Terraform & CI/CD

This repository contains Infrastructure as Code (Terraform) and a GitHub Actions pipeline for deploying a HIPAA-compliant healthcare API and background worker on Azure.

## Prerequisites

- Terraform 1.0+
- Azure CLI (for authentication)
- GitHub repository with Actions enabled
- Azure Subscription

## Structure

```
terraform/
├── modules/                # Reusable Terraform modules
│   ├── networking/        # VNet, subnets, NSGs, Private DNS zones
│   ├── data/             # SQL Server, Storage Account, Private Endpoints
│   └── compute/          # Container Apps, Key Vault, Managed Identity
├── dev/                  # Dev environment configuration
├── qa/                   # QA environment configuration
└── prod/                 # Prod environment configuration

.github/
└── workflows/
    └── terraform.yml     # CI/CD pipeline (plan on PR, apply on merge)

DECISIONS.md              # Architecture decisions, cost analysis, HIPAA controls
```

## Environments

Each environment is structurally identical but scaled differently:

| Aspect | Dev | QA | Prod |
|--------|-----|----|----|
| VNet CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| SQL SKU | Basic | Standard | Premium (ZR) |
| Compute CPU/Memory | 0.25/0.5 Gi | 0.5/1 Gi | 1/2 Gi |
| Storage Replication | LRS | LRS | GRS |
| Estimated Monthly Cost | ~$250 | ~$430 | ~$1465 |

## Deployment

### 1. Local Validation

```bash
cd terraform/dev
terraform init -backend=false
terraform validate
terraform plan -var-file=terraform.tfvars
```

### 2. Deploy via GitHub Actions

- Commit to a branch and open a PR → Workflow runs `terraform plan` for all three environments
- Merge to `main` → Workflow runs `terraform apply` for dev, then qa, then requires manual approval for prod
- Prod approval gate: GitHub Environment protection (requires designated reviewers)

### 3. Manual Azure CLI Deployment (Alternative)

```bash
# Authenticate
az login
az account set --subscription <subscription-id>

# Deploy dev
cd terraform/dev
terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

## Key Architecture Decisions

### Private Connectivity
- **SQL Server & Storage Account** are not publicly accessible.
- **Private Endpoints** in dedicated data subnet (10.x.2.0/24).
- **Private DNS Zones** resolve service names (e.g., `sqlserver-dev-xxx.database.windows.net`) to private IPs.
- **Container Apps** in compute subnet (10.x.1.0/24) reach data services by DNS name only.

### Secrets Management
- **Azure Key Vault** stores database and storage credentials.
- **Managed Identity** (User-Assigned) authenticates Container Apps to Key Vault at runtime.
- **No hardcoded secrets** in config files or environment variables.

### State Management
- **Backend**: Azure Storage Account (`rg-terraform/tfstate`).
- **State Locking**: Enabled via Azure blob leases (prevents concurrent applies).
- **Isolation**: Separate state files for dev, qa, prod (`dev.terraform.tfstate`, etc.).

### HIPAA Compliance
- **Encryption in Transit**: Private Endpoints prevent data traversing the internet.
- **Encryption at Rest**: Storage Account SSE and Key Vault encryption enabled.
- **Access Control**: Least-privilege Managed Identity roles; RBAC for human operators.
- **Audit Logging**: SQL auditing, Key Vault access logs, GitHub Actions audit trail.

See **DECISIONS.md** for detailed rationale on each design choice.

## Cost Optimization

**Overnight cost (dev, ~10 hours)**: ~$2.76  
**Monthly cost (dev)**: ~$250

**Biggest cost lever**: Deallocate Container App instances during non-business hours (saves ~$120/mo in dev).

For detailed cost breakdown and assumptions, see section 5 in DECISIONS.md.

## GitHub Actions Workflow

### On PR (Pull Request)
1. **Plan**: Runs `terraform plan` for dev, qa, and prod environments.
2. **Security Scan**: TFLint + Checkov detect misconfigurations and compliance violations.
3. **Comment**: Posts plan summary to PR for human review.

### On Merge to Main
1. **Apply Dev**: Auto-applies Terraform changes to dev environment.
2. **Apply QA**: Waits for dev to complete, then applies to qa.
3. **Approval Gate**: Pauses before prod; requires manual approval from designated environment reviewers.
4. **Apply Prod**: Applies only after approval is granted.

### Authentication
- **Keyless**: Uses GitHub's OIDC Provider (Workload Identity Federation).
- **No secrets in GitHub**: Credentials are exchanged via Azure Entra ID trust relationship.
- **Least Privilege**: Service Principal has only `Contributor` scope to target resource groups.

## Validation

To validate syntax without deploying:

```bash
cd terraform/dev
terraform init -backend=false
terraform validate

# Check formatting
terraform fmt -check -recursive
```

To detect security & compliance issues:

```bash
pip install checkov tflint
tflint --init && tflint terraform/
checkov -d terraform/ --framework terraform --compact
```

## Next Steps (For Production)

1. **Application Code**: Deploy real API and worker container images.
2. **Disaster Recovery**: Add geo-replication (SQL failover group, Storage geo-redundant read).
3. **Monitoring**: Integrate Application Insights and Azure Monitor.
4. **Secrets Rotation**: Enable Key Vault managed identity password auto-rotation.
5. **Cost Optimization**: Apply SQL Reserved Instances (1 or 3-year terms) for prod.

## Support

See **DECISIONS.md** for design rationale and trade-offs.

---

**Status**: Skeleton complete. Ready for code integration and live deployment.
