output "profile_id" {
  description = "ID of the Azure Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.id
}

output "endpoint_id" {
  description = "ID of the Azure Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.id
}

output "endpoint_hostname" {
  description = "Hostname of the Azure Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "waf_policy_id" {
  description = "ID of the Web Application Firewall policy"
  value       = var.enable_waf ? azurerm_cdn_frontdoor_firewall_policy.main[0].id : null
}

output "private_link_service_id" {
  description = "ID of the private link service"
  value       = "" # Will be configured in phase 2
}
