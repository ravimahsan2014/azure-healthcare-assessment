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

variable "compute_subnet_id" {
  description = "Compute subnet ID for Container Apps Environment"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account ID for role assignment"
  type        = string
}

variable "storage_account_name" {
  description = "Storage account name for connection string"
  type        = string
}

variable "storage_account_key" {
  description = "Storage account access key"
  type        = string
  sensitive   = true
}

variable "sql_server_fqdn" {
  description = "SQL Server fully qualified domain name"
  type        = string
}

variable "sql_database_name" {
  description = "SQL Database name"
  type        = string
}

variable "sql_admin_username" {
  description = "SQL admin username"
  type        = string
}

variable "sql_password" {
  description = "SQL admin password"
  type        = string
  sensitive   = true
}

variable "api_image" {
  description = "Container image for API (e.g., myregistry.azurecr.io/api:latest)"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "api_cpu" {
  description = "CPU for API container"
  type        = string
  default     = "0.5"
}

variable "api_memory" {
  description = "Memory for API container (Gi)"
  type        = string
  default     = "1"
}

variable "worker_image" {
  description = "Container image for worker"
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "worker_cpu" {
  description = "CPU for worker container"
  type        = string
  default     = "0.5"
}

variable "worker_memory" {
  description = "Memory for worker container (Gi)"
  type        = string
  default     = "1"
}
