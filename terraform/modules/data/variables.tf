variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "data_subnet_id" {
  description = "Subnet ID for private endpoints"
  type        = string
}

variable "sql_dns_zone_name" {
  description = "Private DNS Zone name for SQL"
  type        = string
}

variable "storage_dns_zone_name" {
  description = "Private DNS Zone name for Storage"
  type        = string
}

variable "sql_admin_username" {
  description = "SQL Server admin username"
  type        = string
  default     = "sqladmin"
}

variable "sql_sku" {
  description = "SQL Database SKU"
  type        = string
  default     = "Standard"
}
