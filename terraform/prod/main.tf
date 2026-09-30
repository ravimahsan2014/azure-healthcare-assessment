terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-terraform"
    storage_account_name = "tfstate"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment
    managed_by  = "terraform"
    hipaa       = "true"
    pii         = "true"
  }
}

module "networking" {
  source = "../modules/networking"

  environment         = var.environment
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  vnet_cidr           = var.vnet_cidr
  compute_subnet_cidr = var.compute_subnet_cidr
  data_subnet_cidr    = var.data_subnet_cidr
}

module "data" {
  source = "../modules/data"

  environment            = var.environment
  location               = var.location
  resource_group_name    = azurerm_resource_group.main.name
  data_subnet_id         = module.networking.data_subnet_id
  sql_dns_zone_name      = split("/", module.networking.sql_dns_zone_id)[8]
  storage_dns_zone_name  = split("/", module.networking.storage_dns_zone_id)[8]
  sql_sku                = var.sql_sku
}

data "azurerm_storage_account_keys" "main" {
  resource_group_name  = azurerm_resource_group.main.name
  storage_account_name = module.data.storage_account_name
}

module "compute" {
  source = "../modules/compute"

  environment           = var.environment
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  compute_subnet_id     = module.networking.compute_subnet_id
  storage_account_id    = module.data.storage_account_id
  storage_account_name  = module.data.storage_account_name
  storage_account_key   = data.azurerm_storage_account_keys.main.primary_blob_connection_string
  sql_server_fqdn       = module.data.sql_server_fqdn
  sql_database_name     = module.data.sql_database_name
  sql_admin_username    = var.sql_admin_username
  sql_password          = module.data.sql_password
  api_cpu               = var.api_cpu
  api_memory            = var.api_memory
  worker_cpu            = var.worker_cpu
  worker_memory         = var.worker_memory
}
