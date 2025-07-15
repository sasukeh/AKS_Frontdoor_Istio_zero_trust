# Azure Provider Configuration
provider "azurerm" {
  # Skip automatic resource provider registration to avoid timeouts
  skip_provider_registration = true
  
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Random Provider for generating unique names
provider "random" {}

# Data sources
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

# Virtual Network Module
module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  vnet_name         = var.vnet_name
  vnet_address_space = var.vnet_address_space
  
  # Subnets
  aks_subnet_name           = var.aks_subnet_name
  aks_subnet_address_prefix = var.aks_subnet_address_prefix
  pe_subnet_name            = var.pe_subnet_name
  pe_subnet_address_prefix  = var.pe_subnet_address_prefix

  tags = var.tags
}

# AKS Module
module "aks" {
  source = "./modules/aks"

  resource_group_name         = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  cluster_name               = var.aks_cluster_name
  kubernetes_version         = var.aks_kubernetes_version
  
  # Networking
  vnet_subnet_id = module.networking.aks_subnet_id
  vnet_id        = module.networking.vnet_id
  aks_nsg_id     = module.networking.aks_nsg_id
  
  # Node pool configuration
  default_node_pool = {
    name                = "system"
    node_count         = 2
    vm_size           = "Standard_D2s_v3"
    availability_zones = ["1", "2", "3"]
    max_pods          = 30
    os_disk_size_gb   = 30
  }

  additional_node_pools = {
    user = {
      name                = "user"
      node_count         = var.aks_node_count
      vm_size           = var.aks_node_vm_size
      availability_zones = ["1", "2", "3"]
      max_pods          = 50
      os_disk_size_gb   = 100
    }
  }

  # Service Mesh
  service_mesh_profile = {
    mode = "Istio"
  }

  # Monitoring
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  tags = var.tags
}

# Monitoring Module
module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  workspace_name     = var.log_analytics_workspace_name

  tags = var.tags
}

# Azure Front Door Module
module "frontdoor" {
  source = "./modules/frontdoor"

  resource_group_name    = azurerm_resource_group.main.name
  frontdoor_profile_name = var.frontdoor_profile_name
  frontdoor_endpoint_name = var.frontdoor_endpoint_name
  custom_domain          = var.custom_domain
  
  # Backend configuration
  aks_cluster_fqdn = "example.com"  # Temporary placeholder - will be configured after app deployment
  
  # Private endpoint configuration
  pe_subnet_id = module.networking.pe_subnet_id
  
  # WAF configuration
  enable_waf = var.enable_waf

  tags = var.tags

  depends_on = [module.aks]
}

# Kubernetes and Helm providers configuration
provider "kubernetes" {
  host                   = module.aks.kube_config.0.host
  client_certificate     = base64decode(module.aks.kube_config.0.client_certificate)
  client_key            = base64decode(module.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(module.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.kube_config.0.host
    client_certificate     = base64decode(module.aks.kube_config.0.client_certificate)
    client_key            = base64decode(module.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(module.aks.kube_config.0.cluster_ca_certificate)
  }
}
