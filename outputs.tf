output "container_name" {
  value = azurerm_container_group.aci.name
}

output "container_id" {
  value = azurerm_container_group.aci.id
}

output "ports" {
  value = azurerm_container_group.aci.exposed_port
}

