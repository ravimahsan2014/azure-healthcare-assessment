output "resource_group_id" {
  value = azurerm_resource_group.main.id
}

output "vnet_id" {
  value = module.networking.vnet_id
}

output "key_vault_uri" {
  value = module.compute.key_vault_uri
}

output "sql_server_fqdn" {
  value = module.data.sql_server_fqdn
}

output "storage_account_name" {
  value = module.data.storage_account_name
}

output "api_app_id" {
  value = module.compute.api_app_id
}

output "worker_app_id" {
  value = module.compute.worker_app_id
}
