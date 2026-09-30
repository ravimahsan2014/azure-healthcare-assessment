variable "environment" {
  description = "Environment name (dev, qa, prod)"
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

variable "vnet_cidr" {
  description = "CIDR block for VNet"
  type        = string
}

variable "compute_subnet_cidr" {
  description = "CIDR block for compute subnet"
  type        = string
}

variable "data_subnet_cidr" {
  description = "CIDR block for data subnet"
  type        = string
}
