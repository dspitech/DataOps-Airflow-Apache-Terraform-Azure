output "vm_public_ip" {
  description = "IP publique de la VM"
  value       = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  description = "Commande SSH pour se connecter à la VM"
  value       = "ssh -i ~/.ssh/id_rsa_tp6 ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "airflow_ui_url" {
  description = "URL de l'interface Airflow (disponible ~5 min après terraform apply)"
  value       = "http://${azurerm_public_ip.pip.ip_address}:8080"
}

output "airflow_credentials" {
  description = "Identifiants Airflow"
  value       = "login: airflow / password: ${var.airflow_admin_password}"
  sensitive   = true
}

output "storage_connection_string" {
  description = "Connection string du Storage Account Azure"
  value       = azurerm_storage_account.storage.primary_connection_string
  sensitive   = true
}

output "storage_account_name" {
  description = "Nom du Storage Account"
  value       = azurerm_storage_account.storage.name
}

output "resource_group_name" {
  description = "Nom du Resource Group"
  value       = azurerm_resource_group.rg.name
}

output "deployment_note" {
  description = "Note sur le déploiement automatique"
  value       = "cloud-init installe Docker, Airflow, dbt et démarre tout automatiquement. Attendre ~5-8 min avant d'accéder à l'interface web."
}
