# TP 7 - Pipeline DataOps Airflow sur Azure VM - Déploiement 100% automatisé

> **Un seul `terraform apply` suffit.** Infrastructure, Airflow, dbt, DAG, connexion Azure Blob - tout est provisionné et démarré automatiquement.


---

## Vue d'ensemble

Ce TP-7 met en place un **pipeline DataOps de bout en bout** sur Azure, entièrement automatisé via Terraform et cloud-init. L'objectif est de reproduire un workflow professionnel de traitement de données : ingestion depuis le cloud, staging en base locale, transformation analytique et tests qualité - le tout orchestré par Apache Airflow.

### Ce que vous obtenez après `terraform apply`

| Composant | Détail |
|---|---|
| VM Azure Ubuntu 24.04 | 2 vCPU / 8 GB RAM, IP statique |
| Apache Airflow 2.9.3 | Interface web sur port 8080, DAG pré-chargé |
| Azure Blob Storage | Container `raw` pour l'ingestion des fichiers |
| Projet dbt | Modèles analytiques et tests qualité configurés |
| DAG activé | Premier run déclenché automatiquement |

---

## Concepts clés

### Infrastructure as Code (IaC) avec Terraform
Terraform permet de décrire l'infrastructure cloud sous forme de fichiers texte versionnables. Chaque ressource Azure (VM, réseau, stockage) est définie en code HCL. Le même déploiement peut être reproduit à l'identique par n'importe quel membre de l'équipe, ou détruit en une commande (`terraform destroy`).

### cloud-init
Script d'initialisation exécuté **une seule fois** au premier démarrage de la VM. Il installe les dépendances système (Docker, Python, dbt), crée la structure de fichiers, configure les secrets et démarre tous les services — sans aucune intervention humaine.

### Apache Airflow
Orchestrateur de workflows open-source. Il exécute des **DAGs** (Directed Acyclic Graphs) : des pipelines de tâches avec des dépendances, une planification et un suivi des exécutions. L'interface web permet de visualiser l'état de chaque tâche en temps réel.

### dbt (data build tool)
Outil de transformation de données SQL. Il prend des données brutes en entrée, applique des transformations définies en fichiers `.sql`, et produit des tables analytiques propres. Il intègre aussi un système de **tests de qualité** (unicité, nullabilité) pour valider les données produites.

### DAG (Directed Acyclic Graph)
Graphe orienté sans cycle représentant un pipeline de tâches. Chaque nœud est une tâche, chaque flèche une dépendance. "Acyclique" signifie qu'il n'y a pas de boucle : les tâches s'exécutent toujours dans un sens déterminé.

### NSG (Network Security Group)
Pare-feu Azure au niveau réseau. Dans ce TP, il n'autorise que votre IP personnelle à accéder aux ports SSH (22) et Airflow (8080). Tout autre trafic entrant est bloqué.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  MACHINE LOCALE / CLOUD SHELL                                    │
│                                                                  │
│  terraform apply ──────────────────────────────────────────►    │
│  ssh -i ~/.ssh/id_rsa_tp6 dataops_admin@<IP>                    │
│  http://<IP>:8080  (navigateur)                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │ SSH :22 / HTTP :8080
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  AZURE NSG  (filtre : votre IP uniquement)                       │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  AZURE VM Ubuntu 24.04  (Standard_B2ms — 2 vCPU / 8 GB)         │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Docker Compose                                          │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │   │
│  │  │  Airflow    │  │  PostgreSQL  │  │  Redis         │  │   │
│  │  │  Webserver  │  │  (metadata)  │  │  (broker)      │  │   │
│  │  │  Scheduler  │  └──────────────┘  └────────────────┘  │   │
│  │  │  Worker     │                                         │   │
│  │  └──────┬──────┘                                         │   │
│  └─────────┼──────────────────────────────────────────────-─┘   │
│            │ volume monté                                        │
│            ▼                                                     │
│  /home/dataops_admin/dataops-project/                            │
│  ├── airflow/dags/        ← DAG Python                          │
│  ├── scripts/             ← upload_blob.py, load_blob_to_sql.py │
│  ├── dataops_dbt/         ← modèles SQL + tests                 │
│  ├── database/            ← dataops.db (SQLite)                 │
│  └── .dbt/profiles.yml   ← connexion dbt→SQLite                 │
└────────────────────────────────────┬───────────────────────────-┘
                                     │
                                     ▼
                    ┌────────────────────────────┐
                    │  AZURE BLOB STORAGE         │
                    │  Container : raw            │
                    │  dataops/year=.../...json   │
                    └────────────────────────────┘
```

---

## Pipeline DataOps

Le DAG `dataops_pipeline` enchaîne 4 tâches dans l'ordre suivant :

```
upload_blob  ──►  load_sqlite  ──►  dbt_run  ──►  dbt_test
```

### Tâche 1 - `upload_blob`
Génère un fichier JSON horodaté (`{"message": "hello azure...", "timestamp": "..."}`) et l'envoie dans Azure Blob Storage sous le chemin partitionné `dataops/year=YYYY/month=MM/day=DD/test_HHMMSS.json`.

**Pourquoi ?** Simule l'arrivée de données brutes dans un data lake.

### Tâche 2 - `load_sqlite`
Liste tous les blobs du container `raw`, télécharge leur contenu JSON et insère les nouvelles lignes dans la table `stg_blob_files` de la base SQLite. Utilise `INSERT OR IGNORE` pour l'idempotence.

**Pourquoi ?** Constitue la couche **staging** : données brutes chargées en base locale pour le traitement.

### Tâche 3 - `dbt_run`
Exécute les modèles dbt. Le modèle `analytics_messages.sql` sélectionne les messages non nuls depuis `stg_blob_files` et les matérialise dans une table analytique propre.

**Pourquoi ?** Constitue la couche **analytique** : données nettoyées et transformées, prêtes pour la consommation.

### Tâche 4 - `dbt_test`
Exécute les tests de qualité définis dans `schema.yml` : unicité de `source_file`, non-nullité de `source_file` et `message`.

**Pourquoi ?** Garantit la **qualité des données** à chaque exécution. Si un test échoue, Airflow marque la tâche en rouge et alerte.

### Planification
Le DAG tourne toutes les 6 heures (`0 */6 * * *`). Le premier run est déclenché manuellement par le script de déploiement.

---

## Stack technique

| Couche | Technologie | Rôle |
|---|---|---|
| IaC | Terraform 1.5+ | Provisionnement Azure |
| Cloud | Azure VM, Blob Storage, NSG | Infrastructure |
| OS | Ubuntu 24.04 LTS | Système d'exploitation VM |
| Orchestration | Apache Airflow 2.9.3 | Planification et suivi des pipelines |
| Conteneurs | Docker Compose | Déploiement Airflow multi-services |
| Base metadata | PostgreSQL 13 | Stockage état Airflow |
| Message broker | Redis 7.2 | File de messages entre scheduler et worker |
| Staging | SQLite | Base locale légère pour les données brutes |
| Transformation | dbt-core 1.x + dbt-sqlite | Modèles SQL et tests qualité |
| Scripting | Python 3.12 | Scripts d'ingestion (azure-storage-blob) |
| Init VM | cloud-init | Bootstrap automatique au premier démarrage |

---

## Prérequis

- Compte Azure actif avec accès au **Cloud Shell Azure** (bash)
- TPs 1 à 5 terminés - le Storage Account `TP-AZURE-BLOB` doit être fonctionnel
- Clé SSH générée dans le Cloud Shell :

```bash
ssh-keygen -t rsa -b 4096 -C "dataops-tp7-azure" -f ~/.ssh/id_rsa_tp6
```

- Récupérer le dépôt :

```bash
git clone https://github.com/dspitech/DataOps-Airflow-Apache-Terraform-Azure.git
cd DataOps-Airflow-Apache-Terraform-Azure
```

### Vérifier les outils

```bash
az --version && terraform --version
```

---

## Déploiement

### Étape 1 - Récupérer votre IP publique

Cette IP sera autorisée dans le NSG pour SSH et Airflow.

```bash
# Linux / macOS / Cloud Shell
curl -s https://api.ipify.org

# Windows (PowerShell)
(Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
```

### Étape 2 - Configurer terraform.tfvars

Ouvrir `terraform.tfvars` et renseigner les deux valeurs obligatoires :

```hcl
# Votre IP publique récupérée ci-dessus
allowed_ip = "X.X.X.X"

# Nom globalement unique (minuscules + chiffres, max 24 caractères)
storage_account_name = "sadataopstp7votrenom"
```

> **Attention :** `storage_account_name` doit être unique dans tout Azure. Si le déploiement échoue avec une erreur "already taken", changez le suffixe.

### Étape 3 - Déployer

```bash
terraform init && terraform fmt && terraform validate && terraform plan && terraform apply -auto-approve
```

Durée estimée : **2-3 minutes** pour le provisionnement Azure. Le déploiement complet (Airflow + dbt) se termine en **8-12 minutes** en arrière-plan sur la VM.

### Étape 4 - Accéder à Airflow

À la fin de `terraform apply`, notez les outputs affichés :

```
airflow_ui_url  = "http://X.X.X.X:8080"
ssh_command     = "ssh -i ~/.ssh/id_rsa_tp6 dataops_admin@X.X.X.X"
```

Ouvrir `http://<IP_VM>:8080` dans votre navigateur :

```
Login    : airflow
Password : DataOps2026!
```

> Le DAG `dataops_pipeline` est déjà activé et son premier run est en cours ou terminé.

---

## Vérification

### Depuis l'interface Airflow

1. Aller dans **DAGs → dataops_pipeline → Graph**
2. Les 4 tâches doivent être vertes : `upload_blob → load_sqlite → dbt_run → dbt_test`

### Depuis la VM (SSH)

```bash
# Connexion SSH
ssh -i ~/.ssh/id_rsa_tp6 dataops_admin@<IP_VM>

# Suivre les logs du déploiement
tail -f /var/log/deploy_airflow.log

# État des conteneurs Docker
cd ~/dataops-project/airflow
docker compose ps

# Vérifier les données chargées dans SQLite
sqlite3 ~/dataops-project/database/dataops.db \
  "SELECT id, source_file, loaded_at FROM stg_blob_files LIMIT 5;"

# Vérifier la table analytique dbt
sqlite3 ~/dataops-project/database/dataops.db \
  "SELECT * FROM analytics_messages LIMIT 5;"
```

### Résultat attendu pour `docker compose ps`

```
NAME                        STATUS
airflow-airflow-webserver-1  Up (healthy)
airflow-airflow-scheduler-1  Up (healthy)
airflow-airflow-worker-1     Up (healthy)
airflow-postgres-1           Up (healthy)
airflow-redis-1              Up (healthy)
```

---

## Structure du projet sur la VM

```
/home/dataops_admin/dataops-project/
│
├── .env.global                        ← secrets injectés par Terraform (connection string Azure)
│
├── .dbt/
│   └── profiles.yml                   ← connexion dbt vers SQLite (chemin dans le conteneur)
│
├── airflow/
│   ├── .env                           ← variables Docker Compose (UID, password Airflow)
│   ├── docker-compose.yaml            ← téléchargé automatiquement depuis airflow.apache.org
│   ├── dags/
│   │   └── dataops_pipeline_dag.py    ← définition du pipeline (4 tâches)
│   ├── logs/                          ← logs d'exécution des tâches (accessible via UI)
│   └── plugins/                       ← plugins Airflow personnalisés (vide ici)
│
├── dataops_dbt/                       ← projet dbt complet
│   ├── dbt_project.yml                ← configuration du projet dbt
│   └── models/
│       ├── analytics_messages.sql     ← modèle analytique (SELECT depuis stg_blob_files)
│       └── schema.yml                 ← tests de qualité (unique, not_null)
│
├── database/
│   └── dataops.db                     ← base SQLite créée au premier run du DAG
│
├── dbt_models/                        ← fichiers sources copiés par deploy_airflow.sh
│
├── scripts/
│   ├── upload_blob.py                 ← génère et upload un JSON dans Azure Blob
│   └── load_blob_to_sql.py            ← télécharge les blobs et insère dans SQLite
│
└── venv/                              ← environnement Python isolé (dbt + azure-storage-blob)
```

---

## Comment fonctionne l'automatisation

### Flux de déploiement complet

```
terraform apply
    │
    ├── 1. Crée le Resource Group Azure
    ├── 2. Crée le Storage Account + container "raw"
    ├── 3. Crée VNet / Subnet / NSG / IP statique / NIC
    └── 4. Crée la VM Ubuntu avec custom_data = cloud-init
                │
                │  [VM démarre — cloud-init s'exécute automatiquement]
                │
                ├── 5. Installe les paquets système (Docker, Python, sqlite3, git...)
                ├── 6. Écrit tous les fichiers dans /opt/dataops-staging/ (root:root)
                │       ├── scripts Python (upload_blob.py, load_blob_to_sql.py)
                │       ├── DAG Airflow (dataops_pipeline_dag.py)
                │       ├── Fichiers dbt (analytics_messages.sql, schema.yml, dbt_project.yml)
                │       ├── profiles.yml dbt
                │       ├── .env Airflow
                │       └── secrets (.env.global avec connection string Azure)
                ├── 7. Installe Docker + docker-compose-plugin
                └── 8. Lance /opt/deploy_airflow.sh en arrière-plan (nohup)
                            │
                            ├── 9.  Attend la création de l'utilisateur dataops_admin
                            ├── 10. Crée /home/dataops_admin/dataops-project/
                            ├── 11. Copie les fichiers depuis /opt/dataops-staging/
                            ├── 12. Télécharge docker-compose.yaml Airflow officiel
                            ├── 13. Ajoute le volume projet dans docker-compose.yaml
                            ├── 14. Crée le venv Python + installe dbt-sqlite
                            ├── 15. Crée la structure dbt manuellement (sans dbt init)
                            ├── 16. docker compose up airflow-init
                            ├── 17. docker compose up -d  (webserver, scheduler, worker...)
                            ├── 18. Attend que le webserver soit healthy
                            ├── 19. Injecte la variable azure_storage_connection_string
                            ├── 20. airflow dags unpause dataops_pipeline
                            └── 21. airflow dags trigger dataops_pipeline
```

### Pourquoi /opt/dataops-staging/ ?

`write_files` dans cloud-init s'exécute **avant** la création de l'utilisateur `dataops_admin`. Tenter d'écrire directement dans `/home/dataops_admin/` provoque une erreur `Unknown user`. La solution : écrire dans `/opt/dataops-staging/` (appartenant à `root`), puis copier vers le répertoire final une fois l'utilisateur créé.

### Pourquoi sans `dbt init` ?

`dbt init` est une commande interactive : elle pose des questions sur le type d'adapteur et demande confirmation avant d'écraser un `profiles.yml` existant. En environnement non-TTY (script lancé par cloud-init), ces prompts bloquent et font planter le script. La structure dbt est donc créée **manuellement** avec `mkdir` et les fichiers copiés depuis le staging.

---

## Sécurité

| Mesure | Détail |
|---|---|
| **NSG restrictif** | Seule votre IP (`allowed_ip`) peut accéder aux ports 22 et 8080. Tout autre trafic entrant est rejeté. |
| **Clé SSH uniquement** | L'authentification par mot de passe est désactivée sur la VM. Seule la clé RSA 4096 bits générée dans le Cloud Shell est acceptée. |
| **Clé privée dans le Cloud Shell** | La clé privée ne quitte jamais l'environnement Azure. Elle n'est jamais envoyée à un serveur tiers. |
| **Secrets via Variables Airflow** | La connection string Azure n'est pas en clair dans le DAG. Elle est stockée dans les Variables Airflow (chiffrées en base) et injectée au runtime via `{{ var.value.azure_storage_connection_string }}`. |
| **Fichier .env.global en 0600** | Les secrets sur la VM sont lisibles uniquement par `dataops_admin`. |
| **IP statique** | L'IP publique est réservée (allocation `Static`) — elle ne change pas entre redémarrages. |

> **Important :** Si votre IP publique change (réseau mobile, redémarrage box...), mettez à jour `allowed_ip` dans `terraform.tfvars` et relancez `terraform apply`. Le NSG sera mis à jour sans recréer la VM.

---

## Dépannage

### Airflow inaccessible sur :8080

**Cause probable :** votre IP a changé, ou `allowed_ip` est incorrecte.

```bash
# Vérifier votre IP actuelle
curl -s https://api.ipify.org

# Si différente de terraform.tfvars → mettre à jour et relancer
terraform apply -auto-approve
```

### Le déploiement semble bloqué

```bash
# Se connecter en SSH
ssh -i ~/.ssh/id_rsa_tp6 dataops_admin@<IP_VM>

# Voir les dernières lignes du log
tail -100 /var/log/deploy_airflow.log

# Voir l'état cloud-init
sudo cloud-init status --long
```

### Les conteneurs ne démarrent pas

```bash
cd ~/dataops-project/airflow

# État des conteneurs
docker compose ps

# Logs d'un conteneur spécifique
docker compose logs airflow-webserver --tail=50
docker compose logs airflow-scheduler --tail=50

# Relancer si nécessaire
docker compose down && docker compose up -d
```

### DAG en erreur `variable not found`

La variable Airflow n'a pas été injectée automatiquement (injection en fin de déploiement, parfois en léger retard).

1. Aller dans **Admin → Variables** dans l'interface Airflow
2. Vérifier que `azure_storage_connection_string` existe
3. Si absente, l'ajouter manuellement avec la valeur de :

```bash
# Depuis le Cloud Shell dans le dossier terraform
terraform output -raw storage_connection_string
```

### dbt échoue sur `unable to open database file`

Normal lors du premier `dbt debug` (la base SQLite n'existe pas encore). Elle est créée par la tâche `load_sqlite` au premier run du DAG. Ce warning est non-bloquant.

### Relancer le déploiement sans recréer la VM

```bash
ssh -i ~/.ssh/id_rsa_tp6 dataops_admin@<IP_VM>
sudo bash /opt/deploy_airflow.sh
```

---

## Nettoyage

> **Important :** à faire impérativement après le TP pour éviter des coûts Azure.

```bash
# Depuis le Cloud Shell Azure, dans le dossier du projet
terraform destroy -auto-approve
```

Terraform supprimera dans l'ordre : la VM, le disque OS, la NIC, l'IP publique, le NSG, le subnet, le VNet, le Storage Account et le Resource Group.

Vérifier la suppression dans le portail Azure : **Resource Groups → rg-dataops-tp7** (ne doit plus exister).

---

## Glossaire

| Terme | Définition |
|---|---|
| **IaC (Infrastructure as Code)** | Pratique consistant à gérer l'infrastructure cloud via des fichiers de configuration versionnables, plutôt que manuellement via une interface. |
| **Terraform** | Outil IaC open-source d'HashiCorp. Définit l'infrastructure en langage HCL, exécute `plan` (aperçu) puis `apply` (déploiement). |
| **cloud-init** | Standard Linux pour l'initialisation des VM au premier démarrage. Utilisé par tous les grands clouds (Azure, AWS, GCP). |
| **DAG** | Directed Acyclic Graph — graphe orienté sans cycle représentant un pipeline de tâches avec des dépendances. |
| **Airflow** | Orchestrateur de workflows open-source créé par Airbnb. Planifie, exécute et surveille des DAGs via une interface web. |
| **dbt** | Data Build Tool — framework de transformation SQL. Prend des données brutes, applique des modèles SQL et produit des tables analytiques avec tests de qualité intégrés. |
| **Staging** | Couche intermédiaire dans un pipeline de données : données brutes chargées sans transformation, prêtes pour le traitement. |
| **NSG** | Network Security Group — pare-feu Azure au niveau subnet ou NIC. Définit des règles d'autorisation/refus du trafic réseau. |
| **Azure Blob Storage** | Service de stockage objet Azure. Utilisé ici comme data lake pour stocker les fichiers JSON d'ingestion. |
| **SQLite** | Base de données relationnelle embarquée (fichier `.db`). Utilisée comme base de staging légère, sans serveur à déployer. |
| **Docker Compose** | Outil pour définir et exécuter des applications multi-conteneurs. Airflow nécessite 5 services (webserver, scheduler, worker, postgres, redis). |
| **Idempotence** | Propriété d'une opération produisant le même résultat qu'on l'exécute une ou plusieurs fois. Le pipeline utilise `INSERT OR IGNORE` pour garantir cette propriété. |
| **Matérialisation dbt** | Façon dont dbt stocke le résultat d'un modèle : `table` (recréée à chaque run), `view` (requête stockée), `incremental` (ajout des nouvelles lignes seulement). |
| **Connection String** | Chaîne de connexion contenant les informations d'authentification pour accéder à un service (ici Azure Blob Storage). Stockée de façon sécurisée dans les Variables Airflow. |
