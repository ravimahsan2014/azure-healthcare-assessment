variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = "rg-healthcare-dev"
}

variable "vnet_cidr" {
  description = "VNet CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "compute_subnet_cidr" {
  description = "Compute subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "data_subnet_cidr" {
  description = "Data subnet CIDR"
  type        = string
  default     = "10.0.2.0/24"
}

variable "sql_sku" {
  description = "SQL Database SKU"
  type        = string
  default     = "Basic"
}

variable "sql_admin_username" {
  description = "SQL admin username"
  type        = string
  default     = "sqladmin"
}

variable "api_cpu" {
  description = "API container CPU"
  type        = string
  default     = "0.25"
}

variable "api_memory" {
  description = "API container memory (Gi)"
  type        = string
  default     = "0.5"
}

variable "worker_cpu" {
  description = "Worker container CPU"
  type        = string
  default     = "0.25"
}

variable "worker_memory" {
  description = "Worker container memory (Gi)"
  type        = string
  default     = "0.5"
}
