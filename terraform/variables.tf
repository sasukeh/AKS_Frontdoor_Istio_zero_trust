# General Configuration
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-frontdoor-istio-demo"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Japan East"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "frontdoor-istio-demo"
  }
}

# Networking Configuration
variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "vnet-frontdoor-istio"
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_name" {
  description = "Name of the AKS subnet"
  type        = string
  default     = "snet-aks"
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for the AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "pe_subnet_name" {
  description = "Name of the private endpoint subnet"
  type        = string
  default     = "snet-private-endpoint"
}

variable "pe_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet"
  type        = string
  default     = "10.0.2.0/24"
}

# AKS Configuration
variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-frontdoor-istio"
}

variable "aks_kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.30.12"
}

variable "aks_node_count" {
  description = "Number of nodes in the user node pool"
  type        = number
  default     = 3
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "aks_availability_zones" {
  description = "Availability zones for AKS nodes (comma-separated)"
  type        = string
  default     = "2,3"  # Default for Southeast Asia
}

# Azure Front Door Configuration
variable "frontdoor_profile_name" {
  description = "Name of the Azure Front Door profile"
  type        = string
  default     = "afd-frontdoor-istio"
}

variable "frontdoor_endpoint_name" {
  description = "Name of the Azure Front Door endpoint"
  type        = string
  default     = "endpoint-frontdoor-istio"
}

variable "custom_domain" {
  description = "Custom domain for Azure Front Door (optional)"
  type        = string
  default     = ""
}

# Application Configuration
variable "app_name" {
  description = "Name of the sample application"
  type        = string
  default     = "sample-app"
}

variable "app_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "default"
}

variable "frontend_image" {
  description = "Container image for frontend service"
  type        = string
  default     = "nginx:alpine"
}

variable "backend_image" {
  description = "Container image for backend service"
  type        = string
  default     = "node:alpine"
}

# Monitoring Configuration
variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
  default     = "law-frontdoor-istio"
}

variable "enable_monitoring" {
  description = "Enable monitoring and observability features"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_waf" {
  description = "Enable Web Application Firewall"
  type        = bool
  default     = true
}

variable "enable_ddos_protection" {
  description = "Enable DDoS protection (Standard tier)"
  type        = bool
  default     = false
}
