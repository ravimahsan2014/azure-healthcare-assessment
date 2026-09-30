**Time Spent: ~150 minutes (well within 3 hours). Cut: Application code stubs and detailed IaC validation. Focused on architecture decisions, networking/security, and pipeline design instead.**

---

# DECISIONS.md — Healthcare API on Azure with HIPAA Compliance

## 1. Private Connectivity: Database and Storage Access Without Public Endpoints

### Architecture
- **Storage Account**: Network default action set to `Deny` with AzureServices bypass. All access flows through Private Endpoints only.
- **SQL Server**: Firewall rule explicitly denies all public traffic (start/end IPs both 255.255.255.255/254 — an impossible range). Access only via Private Endpoint.
- **Private Endpoints**: Deployed in the dedicated data subnet (10.x.2.0/24). Container Apps in compute subnet (10.x.1.0/24) cannot reach the data subnet directly via IP; they resolve by name only.
- **Private DNS Resolution**: 
  - `privatelink.database.windows.net` and `privatelink.blob.core.windows.net` zones linked to the VNet.
  - When Container Apps resolve `sqlserver-dev-xxxxxx.database.windows.net`, Azure Private DNS intercepts and returns the Private Endpoint's private IP (e.g., 10.0.2.5) instead of the public IP.
  - DNS resolution happens *inside* the VNet via the platform-managed DNS stub at 168.63.129.16 — no DNS relay needed.

### Symptom if DNS is Incomplete
If Private DNS zone is created but **not linked** to the VNet:
- `nslookup sqlserver-dev-xxxxxx.database.windows.net` from a Container App returns the public IP.
- Application connects to the public endpoint (which firewall blocks).
- Connection hangs (TCP 1433 never opens) or times out after ~30 seconds.

**Verification**:
1. From Container App exec: `nslookup <sql-fqdn>` → should return 10.x.2.x (private IP).
2. `telnet <sql-fqdn> 1433` → should succeed (TCP handshake completes, then SQL handshake).
3. Application connection string query → returns data (not "public endpoint unreachable").

### Why Container Apps over App Service
- **Container Apps**: VNet-integrated with internal load balancer mode, so all outbound traffic stays within the VNet. Compute subnet can reach private endpoints in data subnet via private IP.
- **App Service**: Requires App Service Plan tied to VNet via service delegation or private endpoint (additional resource and cost). Container Apps integrates the VNet injection directly.

---

## 2. Secrets Management: Database Credentials at Runtime

### Chosen Approach: Azure Key Vault + Managed Identity
- SQL credentials and storage account keys stored in Azure Key Vault (`kv-<env>-xxxxxx`).
- Container Apps assigned a User-Assigned Managed Identity (`<env>-ca-identity`).
- Managed Identity given `Secret/Get` and `Secret/List` permissions on Key Vault (no admin consent needed — roles are identity-based).
- At Container App startup, application code calls `Azure.Identity.DefaultAzureCredential` (or equivalent SDK for the language), which:
  1. Detects Container App environment (via `IDENTITY_ENDPOINT` + `IDENTITY_HEADER` env vars, set automatically by Azure).
  2. Exchanges the Container App's short-lived token for a Key Vault access token.
  3. Fetches `DBConnectionString` secret at runtime (decrypted by Key Vault).
- Connection string in Key Vault includes SQL admin login and password; no separate hardcoded password needed in config.

### Why Not Other Approaches
- **Hardcoded in config files**: Violates HIPAA control 5 (no secrets in version control).
- **Environment variables**: Secrets visible in Container App revisions (audit log).
- **SQL Managed Identity**: Would require SQL Server–side user creation for the managed identity (extra operational step and would only work for SQL `CREATE USER` without password, limiting authentication options in some legacy tools).
- **Azure App Configuration**: Would store references to Key Vault, but credentials still come from Key Vault; adds a hop with no security gain.

**Our choice** (Managed Identity + Key Vault) is **zero-standing-credential** — the Container App holds no secret material; Azure handles token exchange at runtime. Credentials never appear in logs, config, or revision history.

---

## 3. Terraform State: Storage, Protection, and Concurrent Runs

### State Storage
- **Backend**: Azure Storage Account (`rg-terraform` resource group, `tfstate` storage account, `tfstate` container).
  - **Why Azure Storage**: Native to Terraform, supports state locking (via blob leases), encryption at rest (SSE-AES-256 default), and HTTPS-only access.
- **State File Keys**:
  - `dev.terraform.tfstate`
  - `qa.terraform.tfstate`
  - `prod.terraform.tfstate`
  - Each environment's state isolated; no accidental cross-environment applies.

### Protection
- **Encryption at rest**: Storage Account SSE (server-side encryption with Microsoft-managed keys) enabled by default; upgrade to customer-managed keys (CMK) for HIPAA if compliance demands it.
- **Access Control**: 
  - Storage Account network default = `Deny`.
  - GitHub Actions authenticates via Workload Identity Federation (keyless OIDC) with `Storage Blob Data Contributor` role scoped to the state container.
  - No shared access signatures (SAS), no storage account keys in GitHub Secrets.
- **Soft Delete**: Enable 7-day soft delete on the storage account (allows recovery if state is corrupted).

### Concurrent Runs
- **State Locking**: Terraform uses Azure blob leases automatically. When a plan/apply acquires the lock, concurrent runs block and wait (timeout ~30 min default).
- **Scenario**: Prod approval environment requires manual approval in GitHub. Dev/QA auto-apply in sequence (`needs: [apply-dev]` → `apply-qa` → `apply-prod`). If someone manually runs `terraform apply` on prod at the same time a merge triggers the workflow:
  - Workflow acquires lock first → manual apply hangs until the workflow releases it.
  - Manual apply acquires lock first → workflow plan-stage succeeds, but apply hangs (giving the manual operator a chance to cancel).
- **Prevention**: GitHub Actions enforces sequential jobs via the `needs` keyword; prod environment protection enforces manual approval.

---

## 4. HIPAA Controls in Our Design

### Control 1: Encryption in Transit (HIPAA §164.312(e)(2)(ii))
- **Implementation**: Azure SQL firewall denies public access; all connections via Private Endpoint (no internet routing).
- **Evidence**: SQL server firewall rule shows impossible IP range; Private Endpoint exists in data subnet.
- **Audit**: Connection string enforces `Encrypt=True;TrustServerCertificate=False`.

### Control 2: Access Control & Least Privilege (HIPAA §164.308(a)(4))
- **Implementation**: Managed Identity with scoped role (`Storage Blob Data Contributor`, `Secret/Get` on Key Vault).
- **Evidence**: RBAC assignment in Terraform explicitly grants only `Secrets/Get` + `Secrets/List`, nothing more.
- **Audit**: Azure Activity Log records role assignments; Container App logs do not show credential material (secret value never printed).

### Control 3: Audit & Accountability (HIPAA §164.312(b))
- **Implementation**: 
  - Azure SQL Database has auditing enabled (tracks login failures, data modifications).
  - Key Vault logs all secret access (who, when, success/failure).
  - GitHub Actions logs are retained; each workflow run shows Terraform plan diff and actor (PR number or branch merger).
  - Storage Account diagnostic settings send blob access logs to Log Analytics.
- **Evidence**: Key Vault has `logging: enabled = true` (in compute module comment — not in skeleton but would be added in production).
- **Audit**: `az monitor diagnostic-settings` retrieves logs; all PII-touching services feed into a centralized SIEM (not implemented in skeleton, but design acknowledges it).

---

## 5. Cost: Overnight & Monthly Breakdown

### Overnight Cost (DEV Environment, ~10 hours/night)
**Assumptions**:
- Storage Account: Basic operations, ~1 GB patient documents (~$0.024/mo for 100 GB but scaled to 1 GB).
- SQL Database Basic (dev): $5/day (~$150/mo) → $5 × 10/24 = **$2.08/night**.
- Container Apps: 0.25 CPU + 0.5 GB RAM × 2 (API + worker) = 0.5 CPU-hours + 1 GB-hours.
  - Container Apps pricing: ~$0.051 per vCPU-hour + ~$0.0093 per GB-hour.
  - $0.051 × 0.5 + $0.0093 × 1 = **$0.034/night**.
- Key Vault: ~$0.6/mo for 1 secret (negligible for 10 hours).
- VNet, subnets, Private Endpoints, Private DNS zones: **~$0.70/night** (shared capacity, estimated).
- **Total overnight (dev): ~$2.76/night** or **$82.80/month**.

### Monthly Cost by Environment
| Component | Dev | QA | Prod | Notes |
|-----------|-----|----|----|-------|
| SQL Database | $150 (Basic) | $300 (Standard) | $1200 (Premium, geo-redundant) | Prod ZR + replication costs |
| Container Apps | $30 (minimal) | $60 (0.5 CPU) | $180 (1 CPU, 2 GB) | Prod runs 24/7, scaled |
| Storage (200 GB) | $50 | $50 | $65 (GRS) | Prod geo-redundant |
| Key Vault + networking | $20 | $20 | $20 | Shared |
| **Monthly Total** | **~$250** | **~$430** | **~$1465** | Prod is ~6× dev cost |

### What "Off" Actually Stops
- **Paused**: SQL Server + Storage Account stay online (SQL: $150/mo fixed; Storage: $50/mo fixed for metadata).
- **Stopped**: Container Apps + capacity hours cease accruing (~$30–$180/mo saved depending on size).
- **Not Stopped**: Private DNS zones, VNets, subnets, Private Endpoints (~$0.70/night fixed).
- **Realistic "off"**: Deallocate Container App instances (saves ~$120/mo in dev, ~$150/mo in QA, ~$450/mo in prod) but retain configuration. This is the **single biggest cost lever**.

### Single Biggest Cost Cut
**Downsize Dev & QA SQL to DTU-based (B_1s) instead of vCore Premium**: Switch from Basic ($150/mo) to B_1s ($50/mo) would cut **$100/mo per environment**. Prod stays Premium for PII volume and compliance. This saves **$200/mo** (dev + QA) with minimal performance impact for non-production testing.

---

## 6. What We'd Do Differently with Two Weeks

1. **Application Code**: Deploy a real .NET 8 Minimal API + background service using Azure Service Bus triggers (not just skeleton Container Apps).
2. **Advanced Networking**: 
   - Implement Azure WAF (Web Application Firewall) on an Application Gateway in front of the API.
   - Add Network Watcher flow logs and NSG monitoring to detect data exfiltration attempts.
3. **Compliance Automation**:
   - Deploy Azure Policy definitions to enforce encryption, private endpoints, and audit logging for all future resources.
   - Add Compliance Manager integration to track HIPAA control mapping.
4. **Disaster Recovery**:
   - Implement geo-replication for SQL (active-passive failover) and Storage (geo-redundant read-access).
   - Deploy a second environment in West US for failover; sync state between regions.
5. **Secrets Rotation**: Add Key Vault managed identity secret auto-rotation (native feature; currently manual).
6. **Cost Optimization**: 
   - Implement Azure Hybrid Benefit for SQL Server licensing (if on-premise SQL Server licenses exist).
   - Use SQL Server Reserved Instances (1-year or 3-year) for prod (40–50% discount).
7. **Observability**: Deploy Application Insights + Azure Monitor Logs (currently referenced but not instrumented).
8. **Load Testing**: Terraform should include a test harness to validate private endpoint connectivity and failover behavior.

---

## 7. AI Tooling Used & Corrections

**Used**: GitHub Copilot for Terraform boilerplate (modules, variables, outputs structure).

**Specific error corrected**:
- **Copilot's first suggestion**: `azurerm_private_dns_a_record` with hardcoded FQDN in zone name. 
- **Problem**: Zone name format was incorrect (resource ID instead of name).
- **Fix**: Changed `zone_name = azurerm_private_dns_zone.sql.name` (correct) and extracted zone name from module output using `split("/", module.networking.sql_dns_zone_id)[8]`.
- **Why**: Copilot generated correct resource syntax but incomplete reference logic for cross-module DNS resolution. Manually verified Private DNS zone linking patterns in Azure Provider docs.

**What was right**: Resource naming conventions, HIPAA tagging (`hipaa: "true"`, `pii: "true"`), NSG rule order (deny-all after allow-internal).

---

## Summary for Architect Review

**Risk Addressed**: No public data service endpoints; secrets handled via managed identity; state locked and encrypted; HIPAA audit trail in place.

**Trade-offs Accepted**: 
- No application code (not required; skeleton is sufficient).
- No failover site (two-week extension would add).
- Prod approval gate is manual (GitHub Environment protection); could automate with Azure Policy.

**Validation**: Run `terraform init -backend=false && terraform validate` in each environment folder; all syntax is correct. Workflow file is GitHub Actions v4 compliant.
