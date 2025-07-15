# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Random ID for unique naming
resource "random_id" "cluster" {
  byte_length = 4
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.cluster_name}-${random_id.cluster.hex}"
  kubernetes_version  = var.kubernetes_version

  # Public cluster configuration for simplified access
  private_cluster_enabled             = false

  # Default node pool (system)
  default_node_pool {
    name               = var.default_node_pool.name
    node_count         = var.default_node_pool.node_count
    vm_size           = var.default_node_pool.vm_size
    zones             = var.default_node_pool.availability_zones
    max_pods          = var.default_node_pool.max_pods
    os_disk_size_gb   = var.default_node_pool.os_disk_size_gb
    vnet_subnet_id    = var.vnet_subnet_id
    
    # Only system pods on this node pool
    only_critical_addons_enabled = true
    
    # Enable auto-scaling
    enable_auto_scaling = true
    min_count          = 1
    max_count          = 5

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = "172.16.0.10"
    service_cidr      = "172.16.0.0/16"
    load_balancer_sku = "standard"
  }

  # Identity configuration
  identity {
    type = "SystemAssigned"
  }

  # Remove Azure AD integration for simplicity (will use basic authentication)
  # azure_active_directory_role_based_access_control {
  #   managed = true
  #   azure_rbac_enabled = true
  # }

  # Service mesh profile (Istio)
  dynamic "service_mesh_profile" {
    for_each = var.service_mesh_profile != null ? [var.service_mesh_profile] : []
    content {
      mode = service_mesh_profile.value.mode
    }
  }

  # Monitoring
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # Security features
  role_based_access_control_enabled = true
  
  # Workload identity
  workload_identity_enabled = true
  oidc_issuer_enabled      = true

  # Auto upgrade
  automatic_channel_upgrade = "patch"

  tags = var.tags
}

# Additional node pools
resource "azurerm_kubernetes_cluster_node_pool" "additional" {
  for_each = var.additional_node_pools

  name                  = each.value.name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size              = each.value.vm_size
  node_count           = each.value.node_count
  zones                = each.value.availability_zones
  max_pods             = each.value.max_pods
  os_disk_size_gb      = each.value.os_disk_size_gb
  vnet_subnet_id       = var.vnet_subnet_id

  # Enable auto-scaling
  enable_auto_scaling = true
  min_count          = 1
  max_count          = 10

  # Node taints for user workloads
  node_taints = ["workload=user:NoSchedule"]

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags
}

# Role assignments for AKS cluster identity
resource "azurerm_role_assignment" "network_contributor" {
  scope                = var.vnet_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# VNet level permissions for Private Link Service
resource "azurerm_role_assignment" "vnet_network_contributor" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# NSG level permissions for Private Link Service
resource "azurerm_role_assignment" "nsg_network_contributor" {
  scope                = var.aks_nsg_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# Role assignment for pulling images from ACR (if needed)
resource "azurerm_role_assignment" "acr_pull" {
  count                = var.container_registry_id != null ? 1 : 0
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
