# VPC Peering — HCP Terraform VCS-Driven Workflow + OPA + OIDC

Two VPCs (frontend + backend) in `ap-southeast-1`, peered together. They are deployed by
**7 HCP Terraform workspaces** that a **workspace-runner** creates. Runs are triggered from **GitHub**,
AWS logins use **OIDC** (no access keys), and **OPA** policies are enforced at **project level**.

```
GitHub (feature branch → PR → main)
        │ VCS webhook
        ▼
HCP Terraform org
 ├─ Default Project
 │   └─ workspace-runner      (creates everything below with the tfe provider)
 └─ Project: vpc-peering-vcs-driven   ◄── OPA policy set (project level)
     │   variable set: TFC_AWS_PROVIDER_AUTH, TFC_AWS_RUN_ROLE_ARN, aws_region …
     ├─ fe-network-ws ─► fe-security-ws ─► fe-compute-ws
     ├─ be-network-ws ─► be-security-ws ─► be-compute-ws
     └─ fe-security-ws + be-security-ws ─► vpc-peering
                │ OIDC token
                ▼
AWS  IAM OIDC provider (app.terraform.io) → IAM role → VPCs, subnets, NAT, EC2, peering
```

## What gets built in AWS (per VPC)

| Item | Frontend | Backend |
|---|---|---|
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 |
| Public subnets (3 AZs) | 10.10.0-2.0/24 | 10.20.0-2.0/24 |
| Private subnets (3 AZs) | 10.10.10-12.0/24 | 10.20.10-12.0/24 |
| IGW + 1 NAT GW (public subnet 1) | ✓ | ✓ |
| Route tables | 1 public, 3 private | 1 public, 3 private |
| EC2 | 1 bastion (public) + 3 private | 1 bastion + 3 private |

`vpc-peering` adds the peering connection, the routes between the VPCs, and the **shared SG rules**
(backend allows app port 8080 + ping from the frontend SG, and frontend allows ping from the backend SG).

## Repo layout

```
00-bootstrap-aws-oidc/   run ONCE locally → OIDC provider + IAM role
workspace-runner/        creates project, var set, 7 workspaces, run triggers, OPA policy set
fe-network-ws/  fe-security-ws/  fe-compute-ws/
be-network-ws/  be-security-ws/  be-compute-ws/
vpc-peering/             peering + routes + cross-VPC SG rules
modules/network|security|compute   reused by fe-* and be-*
policies/                OPA: policies.hcl + *.rego   (loaded by HCP Terraform)
policy-tests/            local OPA unit tests
```

Workspaces pass values to each other with **outputs + `terraform_remote_state`**. Nothing is hard-coded:
security reads `vpc_id` from network, compute reads subnet IDs + SG IDs, and peering reads route tables + SGs.

## OPA policies

| Policy | Level | Rule |
|---|---|---|
| mandatory_tags | mandatory | Taggable resources need `Project`, `Environment`, `ManagedBy` |
| allowed_instance_types | mandatory | EC2 must be `t2.micro` or `t3.micro` |
| no_public_ssh | mandatory | No SSH (22) or all-traffic from `0.0.0.0/0` |
| vpc_cidr_range | advisory | VPC CIDR should be inside `10.0.0.0/8` (warning only) |

Test locally: `cd policy-tests && opa test ../policies . -v`

---

# Step-by-step

## Step 0 — Prerequisites
- AWS account, plus AWS CLI configured on your laptop (`aws sts get-caller-identity` works)
- Terraform ≥ 1.6, plus OPA CLI (optional, for tests)
- HCP Terraform org (app.terraform.io)
- GitHub account
- EC2 key pair in ap-southeast-1 (e.g. `lab-key`) if you want to SSH in for testing
- Your public IP: `curl ifconfig.me` → use it as `x.x.x.x/32`

## Step 1 — Push the code to GitHub
```bash
cd vpc-peering-vcs-driven
git init && git add . && git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<you>/vpc-peering-vcs-driven.git
git push -u origin main
```

## Step 2 — Connect GitHub to HCP Terraform
1. HCP Terraform → **Organization Settings → Version Control → Providers → Add a VCS provider → GitHub.com (Custom)**
2. Follow the OAuth steps and authorize.
3. Copy the **OAuth Token ID** (`ot-xxxxxxxxxxxx`). You need it in Step 4.

## Step 3 — Bootstrap OIDC (run once, locally)
```bash
cd 00-bootstrap-aws-oidc
cp terraform.tfvars.example terraform.tfvars   # set tfc_organization
terraform init && terraform apply
terraform output role_arn                      # copy this
```
If you already have an `app.terraform.io` OIDC provider in this AWS account, set `create_oidc_provider = false`.

The IAM role trusts only `organization:<org>:project:vpc-peering-vcs-driven:workspace:*:run_phase:*`.
That means **only workspaces inside this project** can get AWS credentials.

## Step 4 — Create the workspace-runner (manually, once)
1. Create an API token: **User Settings → Tokens → Create**. An org/team token also works.
2. **Workspaces → New → Version control workflow → GitHub → your repo**, name it `workspace-runner`, and keep it in the **Default Project**.
3. Advanced options:
   - Terraform working directory: `workspace-runner`
   - VCS triggers: *Only trigger runs when files in specified paths change*, with pattern `workspace-runner/**/*`
4. Add these variables:

| Key | Category | Value |
|---|---|---|
| `TFE_TOKEN` | env, **sensitive** | token from step 4.1 |
| `tfc_organization` | terraform | your org |
| `github_repo` | terraform | `<you>/vpc-peering-vcs-driven` |
| `oauth_token_id` | terraform | `ot-…` from Step 2 |
| `aws_role_arn` | terraform | from Step 3 |
| `admin_cidr` | terraform | `x.x.x.x/32` |
| `key_name` | terraform | `lab-key` (optional) |

5. **New run → Plan and apply.** This creates the project, the variable set, 7 workspaces, 5 run triggers and the OPA policy set.

## Step 5 — Protect the main branch
GitHub → repo **Settings → Branches → Add rule** for `main`:
- ✅ Require a pull request before merging
- ✅ Require status checks to pass, then pick the `Terraform Cloud/<org>/<workspace>` checks after the first PR shows them

## Step 6 — First deployment
Workspaces were created with `queue_all_runs = false`, so start the chain yourself:
1. Open **fe-network-ws → New run → Plan and apply**
2. Open **be-network-ws → New run → Plan and apply**

Run triggers then flow automatically:
`network → security → compute`, and when both security workspaces finish → `vpc-peering`.

In each run you'll see **Plan → OPA policy check → Apply**.

## Step 7 — Day-2 changes (the real VCS-driven flow)
```bash
git checkout -b feature/fe-network-change
# edit fe-network-ws/...
git commit -am "Change frontend network" && git push -u origin feature/fe-network-change
```
Open a PR. HCP Terraform runs a **speculative plan + OPA check** and posts the result as a PR status check.
Merge, and the real run applies on `main`.

## Step 8 — Prove OPA works
Open a PR that sets `default = "t3.large"` in `fe-compute-ws/variables.tf`.
The PR check **fails** on `allowed_instance_types`. Revert it.

Also try `admin_cidr = "0.0.0.0/0"` in the fe-security-ws workspace variable, then queue a run.
It's blocked by `no_public_ssh`.

## Step 9 — Prove peering works
```bash
ssh -A -i lab-key.pem ec2-user@<fe bastion_public_ip>    # from fe-compute-ws outputs
ssh ec2-user@<fe private ip>                              # hop to frontend private EC2
ping <be private ip>                                      # from be-compute-ws outputs → replies ✔
```
In the AWS console you can also check the route tables (`10.20.0.0/16 → pcx-…`) and the peering status `active`.

## Step 10 — Destroy (reverse order!)
NAT gateways cost money per hour, so destroy when you're done.
Do it in each workspace via **Settings → Destruction and Deletion → Queue destroy plan**:
1. `vpc-peering`
2. `fe-compute-ws`, `be-compute-ws`
3. `fe-security-ws`, `be-security-ws`
4. `fe-network-ws`, `be-network-ws`
5. (optional) `workspace-runner` → removes workspaces/project/policy set
6. (optional) `00-bootstrap-aws-oidc` → `terraform destroy`

## Design notes
- **Routes are separate `aws_route` resources**, not inline `route {}` blocks. Inline blocks would make the
  network workspace delete the peering routes that `vpc-peering` adds.
- **Cross-VPC SG rules live in `vpc-peering`**, not in the security workspaces, because they need both VPCs
  and an active peering connection first.
- **`trigger_patterns`** make each workspace run only when its own folder or its module changes.
- **Remote state sharing** is enabled with `tfe_workspace_settings.global_remote_state`.
