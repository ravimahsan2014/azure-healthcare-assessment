terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# SQL Server
resource "azurerm_mssql_server" "main" {
  name                         = "sqlserver-${var.environment}-${random_string.suffix.result}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = random_password.sql_password.result

  identity {
    type = "SystemAssigned"
  }
}

resource "random_password" "sql_password" {
  length  = 32
  special = true
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  lower   = true
}

# Disable public network access
resource "azurerm_mssql_server_firewall_rule" "deny_all" {
  name             = "DenyAllAzureIps"
  server_id        = azurerm_mssql_server.main.id
  start_ip_address = "255.255.255.255"
  end_ip_address   = "255.255.255.254"
}

# SQL Database
resource "azurerm_mssql_database" "main" {
  name           = "${var.environment}-appdb"
  server_id      = azurerm_mssql_server.main.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  sku_name       = var.sql_sku
  zone_redundant = var.environment == "prod" ? true : false

  # Enable encryption at rest
  transparent_data_encryption_enabled = true
}

# Private Endpoint for SQL
resource "azurerm_private_endpoint" "sql" {
  name                = "${var.environment}-sql-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id

  private_service_connection {
    name                           = "${var.environment}-sql-psc"
    private_connection_resource_id = azurerm_mssql_server.main.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }
}

# Private DNS A Record for SQL
resource "azurerm_private_dns_a_record" "sql" {
  name                = azurerm_mssql_server.main.name
  zone_name           = var.sql_dns_zone_name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address]
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                      = "sa${var.environment}${random_string.suffix.result}"
  resource_group_name       = var.resource_group_name
  location                  = var.location
  account_tier              = "Standard"
  account_replication_type  = var.environment == "prod" ? "GRS" : "LRS"
  https_traffic_only_enabled = true

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  min_tls_version = "TLS1_2"
}

# Storage Blob Container
resource "azurerm_storage_container" "documents" {
  name                  = "patient-documents"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Private Endpoint for Storage
resource "azurerm_private_endpoint" "storage" {
  name                = "${var.environment}-storage-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.data_subnet_id

  private_service_connection {
    name                           = "${var.environment}-storage-psc"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}

# Private DNS A Record for Storage
resource "azurerm_private_dns_a_record" "storage" {
  name                = azurerm_storage_account.main.name
  zone_name           = var.storage_dns_zone_name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
}

# Store SQL password in Key Vault (will be added by compute module)
# Here we export it for the compute module to reference
