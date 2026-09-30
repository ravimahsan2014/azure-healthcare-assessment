terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Key Vault for storing secrets
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.environment}-${random_string.suffix.result}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = var.environment == "prod" ? true : false
  soft_delete_retention_days = 7

  network_rules {
    default_action = "Allow"  # Allow during provisioning; restrict via RBAC
    bypass         = ["AzureServices"]
  }
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  lower   = true
}

data "azurerm_client_config" "current" {}

# Store database credentials in Key Vault
resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "DBConnectionString"
  value        = "Server=tcp:${var.sql_server_fqdn}:1433;Initial Catalog=${var.sql_database_name};Persist Security Info=False;User ID=${var.sql_admin_username};Password=${var.sql_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "StorageConnectionString"
  value        = "DefaultEndpointsProtocol=https;AccountName=${var.storage_account_name};AccountKey=${var.storage_account_key};EndpointSuffix=core.windows.net"
  key_vault_id = azurerm_key_vault.main.id
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                           = "${var.environment}-caenv"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  infrastructure_subnet_id       = var.compute_subnet_id
  internal_load_balancer_enabled = true
}

# Managed Identity for Container Apps
resource "azurerm_user_assigned_identity" "container_apps" {
  name                = "${var.environment}-ca-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Grant Container Apps identity access to Key Vault
resource "azurerm_key_vault_access_policy" "container_apps" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.container_apps.principal_id

  secret_permissions = ["Get", "List"]
}

# Grant Container Apps identity access to Storage
resource "azurerm_role_assignment" "storage" {
  scope              = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id       = azurerm_user_assigned_identity.container_apps.principal_id
}

# Grant Container Apps identity access to SQL (via managed identity)
# This would require additional setup in SQL to create database user for the managed identity
# For now, we'll use connection string from Key Vault which is fetched at runtime

# Container App for API
resource "azurerm_container_app" "api" {
  name                         = "${var.environment}-api"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_apps.id]
  }

  template {
    container {
      name   = "api"
      image  = var.api_image
      cpu    = var.api_cpu
      memory = var.api_memory

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = var.environment
      }

      env {
        name      = "KeyVaultUrl"
        value     = azurerm_key_vault.main.vault_uri
      }
    }
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = false
    target_port                = 5000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [azurerm_key_vault_access_policy.container_apps]
}

# Container App for Worker
resource "azurerm_container_app" "worker" {
  name                         = "${var.environment}-worker"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.container_apps.id]
  }

  template {
    container {
      name   = "worker"
      image  = var.worker_image
      cpu    = var.worker_cpu
      memory = var.worker_memory

      env {
        name  = "ASPNETCORE_ENVIRONMENT"
        value = var.environment
      }

      env {
        name      = "KeyVaultUrl"
        value     = azurerm_key_vault.main.vault_uri
      }
    }
  }

  depends_on = [azurerm_key_vault_access_policy.container_apps]
}
