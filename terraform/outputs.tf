# Resource Group Outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

# Networking Outputs
output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.networking.vnet_id
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = module.networking.aks_subnet_id
}

output "pe_subnet_id" {
  description = "ID of the private endpoint subnet"
  value       = module.networking.pe_subnet_id
}

# AKS Outputs
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = module.aks.cluster_fqdn
}

output "aks_node_resource_group" {
  description = "Resource group containing AKS node resources"
  value       = module.aks.node_resource_group
}

output "kubeconfig" {
  description = "Kubernetes configuration for accessing the cluster"
  value       = module.aks.kube_config_raw
  sensitive   = true
}

# Azure Front Door Outputs
output "frontdoor_endpoint_hostname" {
  description = "Hostname of the Azure Front Door endpoint"
  value       = module.frontdoor.endpoint_hostname
}

output "frontdoor_profile_id" {
  description = "ID of the Azure Front Door profile"
  value       = module.frontdoor.profile_id
}

output "frontdoor_waf_policy_id" {
  description = "ID of the Web Application Firewall policy"
  value       = module.frontdoor.waf_policy_id
}

# Monitoring Outputs
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = module.monitoring.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = module.monitoring.log_analytics_workspace_name
}

# Connection Information
output "connection_info" {
  description = "Information for connecting to the deployed services"
  value = {
    frontdoor_url = "https://${module.frontdoor.endpoint_hostname}"
    aks_cluster   = module.aks.cluster_name
    resource_group = azurerm_resource_group.main.name
    location      = azurerm_resource_group.main.location
  }
}

# Commands for accessing the cluster
output "access_commands" {
  description = "Commands to access the AKS cluster"
  value = {
    get_credentials = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
    kubectl_config  = "kubectl config use-context ${module.aks.cluster_name}"
    istio_check     = "kubectl get pods -n istio-system"
  }
}
