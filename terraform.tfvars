resource_group_name    = "rg-dataops-tp6"
location               = "norwayeast"
vm_name                = "vm-airflow-dataops"
vm_size                = "Standard_B2s"
admin_username         = "dataops_admin"

# Chemin vers la clé publique SSH dans le Cloud Shell
ssh_public_key_path    = "~/.ssh/id_rsa_tp6.pub"

# Remplacez par votre IP publique : curl -s https://api.ipify.org
allowed_ip             = "X.X.X.X"

# Nom unique global (minuscules + chiffres uniquement, max 24 chars)
storage_account_name   = "sadataopstp6unique"

airflow_admin_password = "DataOps2026!"
