output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "compute_subnet_id" {
  value = azurerm_subnet.compute.id
}

output "data_subnet_id" {
  value = azurerm_subnet.data.id
}

output "sql_dns_zone_id" {
  value = azurerm_private_dns_zone.sql.id
}

output "storage_dns_zone_id" {
  value = azurerm_private_dns_zone.storage.id
}
