variable "resource_group_name" {
  description = "Nom du Resource Group"
  type        = string
  default     = "rg-dataops-tp6"
}

variable "location" {
  description = "Région Azure"
  type        = string
  default     = "norwayeast"
}

variable "vm_name" {
  description = "Nom de la VM"
  type        = string
  default     = "vm-airflow-dataops"
}

variable "vm_size" {
  description = "Taille de la VM"
  type        = string
  default     = "Standard_B2ms"
}

variable "admin_username" {
  description = "Nom d'utilisateur admin de la VM"
  type        = string
  default     = "dataops_admin"
}

variable "ssh_public_key_path" {
  description = "Chemin vers la clé publique SSH dans le Cloud Shell"
  type        = string
  default     = "~/.ssh/id_rsa_tp6.pub"
}

variable "allowed_ip" {
  description = "Votre IP publique autorisée pour SSH + Airflow (format : x.x.x.x)"
  type        = string
}

variable "storage_account_name" {
  description = "Nom unique du Storage Account (minuscules, max 24 chars)"
  type        = string
}

variable "airflow_admin_password" {
  description = "Mot de passe admin Airflow"
  type        = string
  sensitive   = true
  default     = "DataOps2026!"
}

variable "tags" {
  description = "Tags communs à toutes les ressources"
  type        = map(string)
  default = {
    project     = "dataops-tp6"
    environment = "dev"
    cours       = "DataOps"
  }
}
