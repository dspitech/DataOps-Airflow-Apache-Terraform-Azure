# TP 6 - DataOps Airflow sur Azure VM - Déploiement 100% automatisé


## Objectifs

À l'issue de ce TP, vous serez capable de :

- Provisionner une VM Linux sur Azure avec Terraform
- Configurer Apache Airflow avec Docker Compose sur une VM distante
- Déployer un DAG DataOps complet sur Airflow
- Exposer l'interface Airflow via un NSG Azure
- Automatiser l'installation avec `cloud-init`
- Utiliser les services Azure gratuits

---

## Architecture complète

```
[Machine locale]
    │  SSH (port 22)
    │  HTTP (port 8080)
    ▼
[Azure NSG] - filtre IP source ──► autorisé
    │
    ▼
[Azure VM Ubuntu 24.04]
    ├── Docker Compose
    │       └── Apache Airflow
    └── /home/dataops_admin/dataops-project/
            ├── airflow/dags/
            ├── database/
            ├── scripts/
            └── dataops_dbt/
```

---

## Pré-requis

- Compte Azure avec accès au **Cloud Shell Azure** 
- TPs 1 à 5 terminés (projet `TP-AZURE-BLOB` fonctionnel)

> **Important** : toutes les commandes des étapes 1 à 9 s'exécutent dans le **Cloud Shell Azure** (bash), accessible depuis le portail Azure. Vous pourrez ensuite vous connecter en SSH depuis votre machine locale une fois la VM créée.

```
terraform apply
      │
      ▼ Azure crée :
      ├── Resource Group
      ├── Storage Account + Container "raw"
      ├── VNet / Subnet / NSG / IP statique / NIC
      └── VM Ubuntu 24.04 avec cloud-init
                │
                ▼ cloud-init fait automatiquement :
                ├── Installe Docker, Python, sqlite3
                ├── Crée toute la structure de dossiers
                ├── Écrit tous les fichiers (scripts, DAG, dbt, .env, profiles.yml)
                ├── Lance deploy_airflow.sh en arrière-plan qui :
                │     ├── Télécharge docker-compose officiel Airflow 2.9.3
                │     ├── Monte le dossier projet dans les conteneurs
                │     ├── Crée le venv Python + installe dbt-sqlite
                │     ├── Initialise le projet dbt (dataops_dbt)
                │     ├── Lance docker compose up airflow-init
                │     ├── Lance docker compose up -d (tous les services)
                │     ├── Injecte la variable azure_storage_connection_string dans Airflow
                │     ├── Active le DAG dataops_pipeline
                │     └── Déclenche un premier run du DAG
                └── Logs dans /var/log/deploy_airflow.log
```

**Après `terraform apply`, vous n'avez qu'à ouvrir http://<IP_VM>:8080 dans votre navigateur.**

---

## Pré-requis

- Cloud Shell Azure avec Terraform disponible (`az --version && terraform --version`)
- Clé SSH générée dans le Cloud Shell :

```bash
ssh-keygen -t rsa -b 4096 -C "dataops-tp6-azure" -f ~/.ssh/id_rsa_tp6
git clone https://github.com/dspitech/DataOps-Airflow-Apache-Terraform-Azure.git
cd DataOps-Airflow-Apache-Terraform-Azure
```

---

## Déploiement

### 1. Récupérer votre IP publique

```
# Linux/macOS
curl -s https://api.ipify.org

# Windows (PowerShell)
(Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
```

### 2. Éditer terraform.tfvars

```hcl
allowed_ip           = "X.X.X.X"          # votre IP publique
storage_account_name = "sadataopstp6uniq"  # unique global, max 24 chars
```

### 3. Déployer

```bash
terraform init && terraform fmt && terraform validate && terraform plan && terraform apply -auto-approve
```

À la fin, notez les outputs :
- `airflow_ui_url` → l'URL à ouvrir dans votre navigateur
- `ssh_command` → pour se connecter si besoin

### 4. Attendre ~5-8 minutes, puis ouvrir Airflow

```
http://<IP_VM>:8080
Login    : airflow
Password : DataOps2026!
```

Le DAG `dataops_pipeline` est déjà activé et son premier run est déclenché automatiquement.

---

## Suivre le déploiement (optionnel)

Si vous voulez observer le déploiement en direct :

```bash
# Se connecter en SSH
ssh -i ~/.ssh/id_rsa_tp6 dataops_admin@<IP_VM>

# Suivre les logs du script de déploiement
tail -f /var/log/deploy_airflow.log

# Ou suivre cloud-init
sudo cloud-init status --wait
```

---

## Structure du projet sur la VM

```
/home/dataops_admin/dataops-project/
├── .env.global                  ← secrets (connection string Azure)
├── .dbt/
│   └── profiles.yml             ← configuration dbt SQLite
├── airflow/
│   ├── .env                     ← config Docker Compose Airflow
│   ├── docker-compose.yaml      ← téléchargé automatiquement
│   └── dags/
│       └── dataops_pipeline_dag.py
├── dataops_dbt/                 ← projet dbt initialisé automatiquement
│   └── models/
│       ├── analytics_messages.sql
│       └── schema.yml
├── database/
│   └── dataops.db               ← créé au premier run du DAG
├── dbt_models/                  ← sources copiées par deploy_airflow.sh
├── scripts/
│   ├── upload_blob.py
│   └── load_blob_to_sql.py
└── venv/                        ← environnement Python avec dbt
```

---

## Nettoyage

```bash
terraform destroy
```

---

## Dépannage

| Problème | Solution |
|---|---|
| Port 8080 inaccessible | Vérifier `allowed_ip` dans `terraform.tfvars` |
| Airflow pas encore disponible | Attendre 5-8 min, vérifier `/var/log/deploy_airflow.log` |
| DAG en erreur `variable not found` | Vérifier les logs - la variable est injectée automatiquement |
| `docker: command not found` au login | cloud-init tourne encore, attendre `sudo cloud-init status` |
| Tout re-déployer sans recréer la VM | `ssh` → `bash /opt/deploy_airflow.sh` |
