# Azure Front Door Profile
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = var.frontdoor_profile_name
  resource_group_name = var.resource_group_name
  sku_name           = "Premium_AzureFrontDoor"

  tags = var.tags
}

# Azure Front Door Endpoint
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = var.frontdoor_endpoint_name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  enabled                  = true

  tags = var.tags
}

# Web Application Firewall Policy
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  count               = var.enable_waf ? 1 : 0
  name                = "waf${replace(var.frontdoor_profile_name, "-", "")}"
  resource_group_name = var.resource_group_name
  sku_name           = azurerm_cdn_frontdoor_profile.main.sku_name
  enabled            = true
  mode               = "Prevention"

  # Managed rules
  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
    action  = "Block"
  }

  # Custom rule for rate limiting
  custom_rule {
    name                           = "RateLimitRule"
    enabled                        = true
    priority                       = 1
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100
    type                          = "RateLimitRule"
    action                        = "Block"

    match_condition {
      match_variable     = "RemoteAddr"
      operator          = "IPMatch"
      negation_condition = false
      match_values      = ["0.0.0.0/0"]
    }
  }

  tags = var.tags
}

# Origin Group
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "aks-backend"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  session_affinity_enabled = false

  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 10

  health_probe {
    interval_in_seconds = 30
    path               = "/healthz"
    protocol           = "Https"
    request_type       = "GET"
  }

  load_balancing {
    additional_latency_in_milliseconds = 50
    sample_size                       = 4
    successful_samples_required       = 3
  }
}

# Private Link Service for AKS connection
# TODO: Configure after AKS cluster is created with load balancer
# resource "azurerm_private_link_service" "aks" {
#   name                = "pls-${var.frontdoor_profile_name}"
#   location            = var.location
#   resource_group_name = var.resource_group_name
#
#   nat_ip_configuration {
#     name      = "primary"
#     primary   = true
#     subnet_id = var.pe_subnet_id
#   }
#
#   # This requires AKS load balancer to be created first
#   load_balancer_frontend_ip_configuration_ids = [
#     # Will be configured in phase 2
#   ]
#
#   tags = var.tags
# }

# Origin (AKS backend)
resource "azurerm_cdn_frontdoor_origin" "aks" {
  name                          = "aks-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true

  certificate_name_check_enabled = true
  host_name                     = var.aks_cluster_fqdn
  http_port                     = 80
  https_port                    = 443
  origin_host_header           = var.aks_cluster_fqdn
  priority                     = 1
  weight                       = 1000

  # Temporarily use direct connection until Private Link is configured
  # private_link {
  #   request_message        = "Private link request from Front Door"
  #   target_type           = "kubernetes_service"
  #   location              = var.location
  #   private_link_target_id = azurerm_private_link_service.aks.id
  # }
}

# Security Policy (WAF association)
resource "azurerm_cdn_frontdoor_security_policy" "main" {
  count                    = var.enable_waf ? 1 : 0
  name                     = "security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.main.id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}

# Route
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.aks.id]
  enabled                       = true

  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]

  cdn_frontdoor_custom_domain_ids = [] # Disabled for initial deployment
  link_to_default_domain         = true
}

# Custom domain (optional) - disabled for initial deployment
# resource "azurerm_cdn_frontdoor_custom_domain" "main" {
#   count                    = var.custom_domain != "" ? 1 : 0
#   name                     = "custom-domain"
#   cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
#   dns_zone_id             = var.dns_zone_id
#   host_name               = var.custom_domain
#
#   tls {
#     certificate_type = "ManagedCertificate"
#     minimum_tls_version = "TLS12"
#   }
# }
