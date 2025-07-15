variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "Japan East"
}

variable "frontdoor_profile_name" {
  description = "Name of the Azure Front Door profile"
  type        = string
}

variable "frontdoor_endpoint_name" {
  description = "Name of the Azure Front Door endpoint"
  type        = string
}

variable "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  type        = string
}

variable "pe_subnet_id" {
  description = "ID of the private endpoint subnet"
  type        = string
}

variable "custom_domain" {
  description = "Custom domain for Azure Front Door (optional)"
  type        = string
  default     = ""
}

variable "dns_zone_id" {
  description = "ID of the DNS zone for custom domain (required if custom_domain is set)"
  type        = string
  default     = null
}

variable "enable_waf" {
  description = "Enable Web Application Firewall"
  type        = bool
  default     = true
}

variable "private_link_service_id" {
  description = "ID of the Private Link Service for AKS Istio Gateway"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
