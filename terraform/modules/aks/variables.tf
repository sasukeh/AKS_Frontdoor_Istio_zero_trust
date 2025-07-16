variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28"
}

variable "vnet_subnet_id" {
  description = "ID of the subnet for AKS nodes"
  type        = string
}

variable "vnet_id" {
  description = "ID of the virtual network for Private Link Service permissions"
  type        = string
}

variable "aks_nsg_id" {
  description = "ID of the AKS network security group for Private Link Service permissions"
  type        = string
}

variable "default_node_pool" {
  description = "Configuration for the default (system) node pool"
  type = object({
    name                = string
    node_count         = number
    vm_size           = string
    availability_zones = list(string)
    max_pods          = number
    os_disk_size_gb   = number
  })
  default = {
    name                = "system"
    node_count         = 2
    vm_size           = "Standard_D2s_v3"
    availability_zones = ["2", "3"]
    max_pods          = 30
    os_disk_size_gb   = 30
  }
}

variable "additional_node_pools" {
  description = "Configuration for additional node pools"
  type = map(object({
    name                = string
    node_count         = number
    vm_size           = string
    availability_zones = list(string)
    max_pods          = number
    os_disk_size_gb   = number
  }))
  default = {}
}

variable "service_mesh_profile" {
  description = "Service mesh configuration"
  type = object({
    mode = string
  })
  default = null
}

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for monitoring"
  type        = string
}

variable "container_registry_id" {
  description = "ID of the Azure Container Registry (optional)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
