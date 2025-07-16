# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# AKS Subnet
resource "azurerm_subnet" "aks" {
  name                 = var.aks_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

# Private Endpoint Subnet
resource "azurerm_subnet" "private_endpoint" {
  name                 = var.pe_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.pe_subnet_address_prefix]

  # Disable private endpoint network policies
  private_endpoint_network_policies = "Disabled"
  # Disable private link service network policies for Private Link Service creation
  private_link_service_network_policies_enabled = false
}

# Network Security Group for AKS Subnet
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-${var.aks_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow HTTPS traffic from Private Endpoint subnet
  security_rule {
    name                       = "AllowHTTPSFromPE"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = var.pe_subnet_address_prefix
    destination_address_prefix = var.aks_subnet_address_prefix
  }

  # Allow HTTP traffic from Private Endpoint subnet (for health checks)
  security_rule {
    name                       = "AllowHTTPFromPE"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "80"
    source_address_prefix     = var.pe_subnet_address_prefix
    destination_address_prefix = var.aks_subnet_address_prefix
  }

  # Allow AKS internal communication
  security_rule {
    name                       = "AllowAKSInternal"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = var.aks_subnet_address_prefix
    destination_address_prefix = var.aks_subnet_address_prefix
  }

  # Allow outbound to Azure services
  security_rule {
    name                       = "AllowAzureServices"
    priority                   = 1001
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = var.aks_subnet_address_prefix
    destination_address_prefix = "AzureCloud"
  }

  tags = var.tags
}

# Network Security Group for Private Endpoint Subnet
resource "azurerm_network_security_group" "private_endpoint" {
  name                = "nsg-${var.pe_subnet_name}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow inbound from Azure Front Door
  security_rule {
    name                       = "AllowAzureFrontDoor"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "AzureFrontDoor.Backend"
    destination_address_prefix = var.pe_subnet_address_prefix
  }

  # Allow outbound to AKS subnet
  security_rule {
    name                       = "AllowToAKS"
    priority                   = 1001
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = var.pe_subnet_address_prefix
    destination_address_prefix = var.aks_subnet_address_prefix
  }

  tags = var.tags
}

# 一時的な公開アクセス用NSGルール（テスト後に削除予定）
resource "azurerm_network_security_rule" "allow_http_test" {
  name                        = "Allow-HTTP-Test"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = "*"  # 一時的に全ての送信元を許可
  destination_address_prefix = "*"
  resource_group_name        = var.resource_group_name  # 正しい変数参照
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_network_security_rule" "allow_https_test" {
  name                        = "Allow-HTTPS-Test"
  priority                    = 301
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "443"
  source_address_prefix      = "*"  # 一時的に全ての送信元を許可
  destination_address_prefix = "*"
  resource_group_name        = var.resource_group_name  # 正しい変数参照
  network_security_group_name = azurerm_network_security_group.aks.name
}

# Associate NSG with AKS Subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Associate NSG with Private Endpoint Subnet
resource "azurerm_subnet_network_security_group_association" "private_endpoint" {
  subnet_id                 = azurerm_subnet.private_endpoint.id
  network_security_group_id = azurerm_network_security_group.private_endpoint.id
}
