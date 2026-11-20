output "project_id" {
  value = tfe_project.this.id
}

output "workspace_ids" {
  value = { for k, ws in tfe_workspace.this : k => ws.id }
}

output "run_triggers" {
  value = keys(local.run_triggers)
}

output "policy_set_id" {
  value = tfe_policy_set.opa.id
}
