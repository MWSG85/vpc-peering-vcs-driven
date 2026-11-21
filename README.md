# VPC Peering — HCP Terraform VCS-Driven Workflow + OPA + OIDC

Two AWS VPCs (frontend and backend) in `ap-southeast-1`, connected by VPC peering.
Everything is deployed by **HCP Terraform** from a **GitHub** repo:

- **VCS-driven workflow:** a merge to `main` triggers runs automatically
- **OIDC dynamic credentials:** HCP Terraform logs in to AWS with short-lived tokens, so **no AWS access keys** are stored anywhere
- **OPA policy as code:** every plan is checked against policies before apply, enforced at **project level**
- **workspace-runner:** a workspace that **creates the other workspaces** with the `tfe` provider ("Terraform managing Terraform")

---

## Architecture

```
Engineer laptop ──git push──► GitHub (feature branch → PR → main, branch protected)
                                   │ webhook (VCS integration)
                                   ▼
HCP Terraform org
 ├─ Default Project
 │   └─ workspace-runner      creates project, workspaces, variable set,
 │                            run triggers and the OPA policy set (tfe provider)
 └─ Project: vpc-peering-vcs-driven   ◄── OPA policy set (project level)
     │   variable set: TFC_AWS_PROVIDER_AUTH, TFC_AWS_RUN_ROLE_ARN, aws_region …
     ├─ fe-network-ws ─► fe-security-ws ─► fe-compute-ws
     ├─ be-network-ws ─► be-security-ws ─► be-compute-ws
     └─ fe-security-ws + be-security-ws ─► vpc-peering
                │ OIDC token (app.terraform.io)
                ▼
AWS  IAM OIDC provider → IAM role (trusts only this org + project)
     → VPCs, subnets, IGW, NAT, route tables, SGs, EC2, VPC peering
```

**Two kinds of triggers**
- **VCS trigger (GitHub → HCP Terraform):** a merge to `main` starts the workspaces whose folder changed (trigger patterns)
- **Run trigger (workspace → workspace):** when a workspace finishes applying, HCP Terraform starts the workspaces that depend on it. GitHub is not involved.

---

## What gets built in AWS

| Item | Frontend | Backend |
|---|---|---|
| VPC CIDR | **10.6.0.0/16** | **172.16.0.0/16** |
| Public subnets (3 AZs) | 10.6.0.0/24, 10.6.1.0/24, 10.6.2.0/24 | 172.16.0.0/24, 172.16.1.0/24, 172.16.2.0/24 |
| Private subnets (3 AZs) | 10.6.10.0/24, 10.6.11.0/24, 10.6.12.0/24 | 172.16.10.0/24, 172.16.11.0/24, 172.16.12.0/24 |
| Internet gateway + 1 NAT gateway (public subnet 1) | ✓ | ✓ |
| Route tables | 1 public + 3 private | 1 public + 3 private |
| Security groups | public SG (bastion) + private SG | public SG (bastion) + private SG |
| EC2 (t3.micro) | 1 public + 3 private | 1 public + 3 private |

`vpc-peering` adds:
- the peering connection (same account and region, so `auto_accept = true`)
- routes in **all** route tables: frontend `172.16.0.0/16 → pcx-…`, backend `10.6.0.0/16 → pcx-…`
- **shared (cross-VPC) security group rules**: backend private SG allows TCP 8080 + ICMP from the frontend private SG, and frontend private SG allows ICMP from the backend private SG

---

## Repo layout

```
00-bootstrap-aws-oidc/   run ONCE from a laptop → OIDC provider + IAM role (local state)
workspace-runner/        creates project, variable set, 7 workspaces, run triggers, OPA policies
fe-network-ws/  fe-security-ws/  fe-compute-ws/
be-network-ws/  be-security-ws/  be-compute-ws/
vpc-peering/             peering + routes + cross-VPC SG rules
modules/network|security|compute   reused by fe-* and be-*
policies/                OPA rules (*.rego), uploaded by workspace-runner
policy-tests/            local OPA unit tests (opa test ../policies . -v)
```

**Passing values between workspaces:** each workspace publishes **outputs**, and the next one reads
them with `terraform_remote_state`. Nothing is hard-coded: security reads `vpc_id` from network,
compute reads subnet IDs and SG IDs, and peering reads route tables and SGs from both sides.

---

## OPA policies

| Policy | Mode | Rule |
|---|---|---|
| allowed-instance-types | **mandatory** (blocks apply) | EC2 must be `t2.micro` or `t3.micro` |
| mandatory-tags | advisory (warning) | Taggable resources need `Project`, `Environment`, `ManagedBy` |
| no-public-ssh | advisory (warning) | No SSH (22) or all-traffic from `0.0.0.0/0` |
| vpc-cidr-range | advisory (warning) | VPC CIDR must be private RFC1918 (10/8, 172.16/12, 192.168/16) |

**Mandatory vs advisory**
- **Mandatory:** a failure **stops the run before apply**. Nothing reaches AWS.
- **Advisory:** a failure shows a **warning**, and the apply continues.

**Free plan notes**
- The HCP Terraform Free plan does **not** allow VCS-connected ("versioned") policy sets, so each
  `.rego` file is uploaded as an **individually managed policy** (`tfe_policy`) by workspace-runner,
  grouped into a policy set, and attached to the project.
- The Free plan allows only **1 mandatory policy**, so the other three are advisory.
  On a paid plan, `no-public-ssh` and `mandatory-tags` would also be mandatory.
- `policies/policies.hcl` is only used by VCS-connected policy sets and is kept for reference.

**Run local tests:** `cd policy-tests && opa test ../policies . -v`

---

# How it was built (step by step)

## Step 0 — Prerequisites
- AWS account + AWS CLI configured (`aws sts get-caller-identity`)
- Terraform ≥ 1.6, OPA CLI (optional, for tests)
- HCP Terraform organization (app.terraform.io)
- GitHub account
- Your public IP: `curl ifconfig.me` → use as `x.x.x.x/32`

## Step 1 — Push the code to GitHub
```bash
git init && git add . && git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<you>/vpc-peering-vcs-driven.git
git push -u origin main
```

## Step 2 — Connect GitHub to HCP Terraform
1. HCP Terraform → **Settings → Version Control → Providers → Add a VCS provider → GitHub → GitHub.com (Custom)**
2. Register a GitHub **OAuth App** with the values HCP Terraform shows (homepage + callback URL)
3. Paste the Client ID and Client Secret → **Connect and continue** → **Authorize** → **Skip and finish**
4. Copy the **OAuth Token ID** (`ot-…`). workspace-runner needs it.

## Step 3 — Bootstrap OIDC (run once, locally)
Chicken-and-egg problem: HCP Terraform needs an IAM role to log in to AWS, but something must create
that role first. So this folder runs **once from a laptop** with your own AWS credentials.
```bash
cd 00-bootstrap-aws-oidc
cp terraform.tfvars.example terraform.tfvars   # set tfc_organization
terraform init && terraform apply
terraform output role_arn
```
It creates:
- an **IAM OIDC provider** that trusts `app.terraform.io` (audience `aws.workload.identity`)
- an **IAM role** that only runs from `organization:<org>:project:vpc-peering-vcs-driven:workspace:*:run_phase:*` can assume

Keep this folder: its local `terraform.tfstate` is needed to destroy the role later.

## Step 4 — workspace-runner (created manually, once)
1. Create a **user API token**: Account settings → Tokens → Create an API token
2. **Workspaces → New → Version control workflow → GitHub → repo**, name `workspace-runner`, in **Default Project**
   - Working directory: `workspace-runner`
   - Trigger patterns: `workspace-runner/**/*` **and** `policies/**/*`
   - Auto-apply: **off** (review each change)
3. Variables:

| Key | Category | Value |
|---|---|---|
| `TFE_TOKEN` | **env**, sensitive | user API token |
| `tfc_organization` | terraform | org name (exact spelling) |
| `github_repo` | terraform | `<owner>/<repo>`, **not** the full URL |
| `oauth_token_id` | terraform | `ot-…` from Step 2 |
| `aws_role_arn` | terraform | from Step 3 |
| `admin_cidr` | terraform | `x.x.x.x/32` |
| `key_name` | terraform | optional EC2 key pair name |

4. **New run → Plan and apply → Confirm & Apply**

workspace-runner lives in **Default Project** on purpose: it creates the lab project (so it can't live
inside it), it can destroy that project without deleting itself, and the AWS role does not trust it,
so it can never touch AWS (least privilege).

## Step 5 — Protect `main`
GitHub → Settings → Branches → rule for `main`:
- ✅ Require a pull request before merging
- ✅ **Do not allow bypassing the above settings** (otherwise admins can still push directly)
- On GitHub Free, branch protection is only enforced on **public** repos

## Step 6 — First deployment (via PR)
1. Feature branch → change → push → **Pull Request**
2. Merge → the changed **network** workspaces start from GitHub
3. Run triggers chain the rest automatically: network → security → compute, and both security workspaces → vpc-peering
4. All 7 workspaces show **Applied**, and `vpc-peering` output `peering_status = "active"`

`vpc-peering` may error once with "No stored state was found" if one side finishes first. That's
harmless: it re-runs automatically when the other security workspace finishes.

## Step 7 — OPA test
Changed `fe-compute-ws` instance type to `t3.large` and merged.
**Result:** `OPA policies failed` → `allowed-instance-types (mandatory)` → all 4 frontend
instances flagged → **run stopped before apply, nothing changed in AWS**. Reverted with another PR.

## Step 8 — Verify in AWS
- VPC → Peering connections → `frontend-to-backend-peering` = **Active**
- Route tables → frontend has `172.16.0.0/16 → pcx-…`, backend has `10.6.0.0/16 → pcx-…`
- Security groups → backend private SG allows ICMP + 8080 from the frontend private SG
- EC2 → 8 instances, all `t3.micro`

## Step 9 — Destroy (reverse order)
NAT gateways cost money per hour. In each workspace: **Settings → Destruction and Deletion → Queue destroy plan**
1. `vpc-peering`
2. `fe-compute-ws`, `be-compute-ws`
3. `fe-security-ws`, `be-security-ws`
4. `fe-network-ws`, `be-network-ws`
5. (optional) `workspace-runner` → removes workspaces, project, variable set and policies
6. (optional) `00-bootstrap-aws-oidc` → `terraform destroy`

---

## Issues hit and lessons learned

| Problem | Cause | Fix |
|---|---|---|
| `resource not found` creating project / variable set | Org name typo in `tfc_organization` | Use the exact org name |
| "Authentication method has limited TFE provider permissions" | `TFE_TOKEN` missing or not an **env** variable | Add `TFE_TOKEN` as an Environment variable, sensitive |
| Workspaces failed to connect to the repo | `github_repo` was the full `https://…git` URL | Use `owner/repo` only |
| "limit of 0 versioned policy sets" | Free plan has no VCS-connected policy sets | Upload policies individually (`tfe_policy`) |
| "limit of 1 mandatory policy" | Free plan limit | 1 mandatory + 3 advisory; re-run if the first run races |
| Merge didn't start `be-network-ws` | Workspace had never had a run (`queue_all_runs = false`) | One manual run per workspace; better: `queue_all_runs = true` |
| Empty commits didn't re-trigger PR plans | HCP Terraform only runs when files matching the trigger patterns change | Change a real file in the workspace folder |
| Direct push to protected `main` was "bypassed" | Admins can bypass by default | Tick "Do not allow bypassing the above settings" |
| No speculative plans on PRs, and "Repository doesn't exist or isn't accessible" when saving VCS settings | Still under investigation (GitHub webhooks were delivered with 200) | OPA was verified on the merged run instead |

---

## Design notes
- **Routes are separate `aws_route` resources**, not inline `route {}` blocks. Inline blocks would make
  the network workspace delete the peering routes that `vpc-peering` adds.
- **Cross-VPC SG rules live in `vpc-peering`**, because they need both VPCs and an active peering connection.
- **`trigger_patterns`** make each workspace run only when its own folder or its module changes.
- **Remote state sharing** is enabled with `tfe_workspace_settings.global_remote_state`.
- **CIDRs must not overlap**, or VPC peering is rejected by AWS.

## Real-world improvements (beyond this lab)
- **Transit Gateway** instead of peering when there are more than a few VPCs (peering is not transitive)
- **Separate AWS accounts** (network / dev / prod) → peering needs an accepter resource in the other account
- **Least-privilege OIDC:** one role per workspace, separate plan (read-only) and apply roles, trust scoped to the exact workspace
- **Modules in a private registry** with versions, instead of `../modules`
- **Policies in a separate repo** owned by the security team, baseline policies at org level, new policies rolled out advisory → mandatory
- **SSM Session Manager** instead of bastion + SSH keys; one NAT gateway per AZ in production
- **`auto_apply = false`** and required PR reviews for production
