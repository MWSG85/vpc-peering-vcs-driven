# workspace-runner = "workspace that builds the workspaces".
# It creates in HCP Terraform:
#   1. Project
#   2. Project variable set (OIDC env vars + shared Terraform vars)
#   3. 7 VCS-driven workspaces (one per folder)
#   4. Remote state sharing + run triggers (the dependency chain)
#   5. OPA policy set from /policies, attached at PROJECT level

locals {
  # name => folder + module folders that should also trigger a run
  workspaces = {
    "fe-network-ws"  = { dir = "fe-network-ws", modules = ["modules/network"] }
    "fe-security-ws" = { dir = "fe-security-ws", modules = ["modules/security"] }
    "fe-compute-ws"  = { dir = "fe-compute-ws", modules = ["modules/compute"] }
    "be-network-ws"  = { dir = "be-network-ws", modules = ["modules/network"] }
    "be-security-ws" = { dir = "be-security-ws", modules = ["modules/security"] }
    "be-compute-ws"  = { dir = "be-compute-ws", modules = ["modules/compute"] }
    "vpc-peering"    = { dir = "vpc-peering", modules = [] }
  }

  # consumer => sources. When a source applies, the consumer gets a run.
  #   fe-network -> fe-security -> fe-compute
  #   be-network -> be-security -> be-compute
  #   fe-security + be-security -> vpc-peering
  dependencies = {
    "fe-security-ws" = ["fe-network-ws"]
    "fe-compute-ws"  = ["fe-security-ws"]
    "be-security-ws" = ["be-network-ws"]
    "be-compute-ws"  = ["be-security-ws"]
    "vpc-peering"    = ["fe-security-ws", "be-security-ws"]
  }

  run_triggers = merge([
    for consumer, sources in local.dependencies : {
      for src in sources : "${src}->${consumer}" => { consumer = consumer, source = src }
    }
  ]...)
}

# ---------- 1. Project ----------
resource "tfe_project" "this" {
  name = var.project_name
}

# ---------- 2. Variable set for the whole project ----------
resource "tfe_variable_set" "project" {
  name        = "${var.project_name}-shared"
  description = "OIDC auth to AWS + shared vars for all workspaces in ${var.project_name}"
}

resource "tfe_project_variable_set" "project" {
  project_id      = tfe_project.this.id
  variable_set_id = tfe_variable_set.project.id
}

# OIDC / dynamic provider credentials (env vars)
resource "tfe_variable" "aws_provider_auth" {
  variable_set_id = tfe_variable_set.project.id
  category        = "env"
  key             = "TFC_AWS_PROVIDER_AUTH"
  value           = "true"
}

resource "tfe_variable" "aws_run_role_arn" {
  variable_set_id = tfe_variable_set.project.id
  category        = "env"
  key             = "TFC_AWS_RUN_ROLE_ARN"
  value           = var.aws_role_arn
}

# Shared Terraform variables
resource "tfe_variable" "shared" {
  for_each = {
    aws_region       = var.aws_region
    tfc_organization = var.tfc_organization
    project          = var.project_name
    environment      = var.environment
  }

  variable_set_id = tfe_variable_set.project.id
  category        = "terraform"
  key             = each.key
  value           = each.value
}

# ---------- 3. Workspaces (VCS-driven) ----------
resource "tfe_workspace" "this" {
  for_each = local.workspaces

  name              = each.key
  project_id        = tfe_project.this.id
  working_directory = each.value.dir

  # Only run when this folder (or the module it uses) changes
  file_triggers_enabled = true
  trigger_patterns      = concat(["${each.value.dir}/**/*"], [for m in each.value.modules : "${m}/**/*"])

  queue_all_runs         = false # don't start all 7 at once on creation
  speculative_enabled    = true  # plan-only runs on pull requests
  auto_apply             = var.auto_apply
  auto_apply_run_trigger = var.auto_apply

  vcs_repo {
    identifier     = var.github_repo
    branch         = var.github_branch
    oauth_token_id = var.oauth_token_id
  }
}

# ---------- 4a. Remote state sharing ----------
resource "tfe_workspace_settings" "this" {
  for_each = tfe_workspace.this

  workspace_id        = each.value.id
  execution_mode      = "remote"
  global_remote_state = true
}

# Per-workspace variables
resource "tfe_variable" "admin_cidr" {
  for_each = toset(["fe-security-ws", "be-security-ws"])

  workspace_id = tfe_workspace.this[each.key].id
  category     = "terraform"
  key          = "admin_cidr"
  value        = var.admin_cidr
}

resource "tfe_variable" "key_name" {
  for_each = var.key_name == "" ? toset([]) : toset(["fe-compute-ws", "be-compute-ws"])

  workspace_id = tfe_workspace.this[each.key].id
  category     = "terraform"
  key          = "key_name"
  value        = var.key_name
}

# ---------- 4b. Run triggers (dependency chain) ----------
resource "tfe_run_trigger" "this" {
  for_each = local.run_triggers

  workspace_id  = tfe_workspace.this[each.value.consumer].id
  sourceable_id = tfe_workspace.this[each.value.source].id
}

# ---------- 5. OPA policies (individually managed - works on the Free plan) ----------
# Free plan does not allow VCS-connected ("versioned") policy sets, so each .rego
# file in /policies is uploaded as its own tfe_policy, then grouped into a set.
locals {
  opa_policies = {
    mandatory_tags = {
      file  = "mandatory_tags.rego"
      query = "data.terraform.policies.mandatory_tags.deny"
      mode  = "advisory"
    }
    allowed_instance_types = {
      file  = "instance_type.rego"
      query = "data.terraform.policies.instance_type.deny"
      mode  = "mandatory"
    }
    no_public_ssh = {
      file  = "no_public_ssh.rego"
      query = "data.terraform.policies.no_public_ssh.deny"
      mode  = "advisory"
    }
    vpc_cidr_range = {
      file  = "vpc_cidr.rego"
      query = "data.terraform.policies.vpc_cidr.deny"
      mode  = "advisory"
    }
  }
}

resource "tfe_policy" "opa" {
  for_each = local.opa_policies

  name         = replace(each.key, "_", "-")
  description  = "OPA policy ${each.key} for ${var.project_name}"
  kind         = "opa"
  query        = each.value.query
  enforce_mode = each.value.mode
  policy       = file("${path.module}/../policies/${each.value.file}")
}

resource "tfe_policy_set" "opa" {
  name        = "${var.project_name}-opa"
  description = "OPA guardrails for ${var.project_name}"
  kind        = "opa"
  overridable = false
  policy_ids  = [for p in tfe_policy.opa : p.id]
}

resource "tfe_project_policy_set" "opa" {
  project_id    = tfe_project.this.id
  policy_set_id = tfe_policy_set.opa.id
}
