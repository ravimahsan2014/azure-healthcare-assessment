output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "container_app_environment_id" {
  value = azurerm_container_app_environment.main.id
}

output "api_app_id" {
  value = azurerm_container_app.api.id
}

output "worker_app_id" {
  value = azurerm_container_app.worker.id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.container_apps.principal_id
}
