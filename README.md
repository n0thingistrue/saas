# Infrastructure SaaS Haute Disponibilité - RNCP37680

## Vue d'ensemble

Infrastructure SaaS sécurisée en haute disponibilité déployée sur 2 nodes Kubernetes (K3s)
dans le cadre de la certification RNCP37680 - Administrateur Systèmes, Réseaux et Sécurité.

### Objectifs

| Métrique | Cible |
|----------|-------|
| SLA | 99.5% (43.8h downtime max/an) |
| RTO | < 1 heure |
| RPO | < 15 minutes |
| Conformité | ISO 27001 + RGPD |
| Sécurité | Defense in Depth |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        INTERNET                                  │
│                           │                                      │
│                    ┌──────┴──────┐                               │
│                    │ Floating IP │                               │
│                    │ + DNS       │                               │
│                    └──────┬──────┘                               │
│                           │                                      │
│              ┌────────────┴────────────┐                        │
│              │    Hetzner Cloud LB     │                        │
│              └────────┬───────┬────────┘                        │
│                       │       │                                  │
│    ┌──────────────────┴─┐   ┌┴──────────────────┐              │
│    │     NODE 1          │   │     NODE 2         │              │
│    │  16vCPU / 32GB      │   │  4vCPU / 16GB      │              │
│    │                     │   │                     │              │
│    │  K3s Control Plane  │   │  K3s Worker         │              │
│    │  PostgreSQL Primary │◄──►  PostgreSQL Standby │              │
│    │  Redis Master       │◄──►  Redis Replica      │              │
│    │  Backend (2/3)      │   │  Backend (1/3)      │              │
│    │  Frontend (1/2)     │   │  Frontend (1/2)     │              │
│    │  Samba-AD Primary   │   │  Wazuh Agent        │              │
│    │  Monitoring Stack   │   │  Staging (on-demand)│              │
│    │  Traefik Ingress    │   │                     │              │
│    └─────────────────────┘   └─────────────────────┘              │
│              │                         │                          │
│              └────────┬────────────────┘                          │
│                       │                                           │
│              ┌────────┴────────┐                                 │
│              │  WireGuard VPN  │                                 │
│              │  (inter-node)   │                                 │
│              └─────────────────┘                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Stack technique

| Composant | Technologie | Version |
|-----------|------------|---------|
| Orchestration | K3s | v1.29.x |
| Frontend | Next.js (SSR) | 14.x |
| Backend | NestJS (REST + GraphQL) | 10.x |
| Base de données | PostgreSQL + Patroni | 16.x |
| Cache | Redis Sentinel | 7.2.x |
| Authentification | Samba-AD (LDAP/Kerberos/SSO) | 4.19.x |
| Ingress | Traefik + ModSecurity WAF | 3.x |
| Monitoring | Prometheus + Grafana + Loki | latest |
| Sécurité | Wazuh, fail2ban, WireGuard | latest |
| GitOps | ArgoCD | 2.10.x |
| Backup | WAL-G + Hetzner S3 | latest |
| IaC | Terraform | 1.7.x |
| CI/CD | GitHub Actions | - |

### Infrastructure

| Node | Specs | Provider | Coût |
|------|-------|----------|------|
| Node 1 | 16 vCPU, 32GB RAM, 320GB | Hetzner CCX33 | ~25€/mois |
| Node 2 | 4 vCPU, 16GB RAM, 160GB | Hetzner CCX23 | ~10€/mois |

**Budget total estimé : ~35€/mois** (serveurs + stockage S3 + floating IP)

## Structure du projet

```
saas/
├── terraform/                  # Infrastructure as Code (Hetzner Cloud)
│   ├── environments/           # Variables par environnement
│   │   ├── prod/
│   │   └── staging/
│   └── modules/                # Modules Terraform réutilisables
│       ├── server/
│       ├── network/
│       ├── firewall/
│       ├── volume/
│       └── s3/
├── kubernetes/                 # Manifests Kubernetes
│   ├── base/                   # Ressources de base (namespaces, RBAC, policies)
│   ├── apps/                   # Déploiements applicatifs
│   │   ├── frontend/           # Next.js SSR
│   │   ├── backend/            # NestJS REST + GraphQL
│   │   ├── postgresql/         # PostgreSQL Patroni HA
│   │   ├── redis/              # Redis Sentinel HA
│   │   └── samba-ad/           # Samba Active Directory
│   ├── ingress/                # Traefik, cert-manager, WAF
│   ├── secrets/                # SealedSecrets (chiffrés)
│   └── overlays/               # Kustomize overlays prod/staging
├── monitoring/                 # Stack observabilité
│   ├── prometheus/             # Prometheus + ServiceMonitors
│   ├── grafana/                # Dashboards + datasources
│   ├── loki/                   # Agrégation logs
│   ├── promtail/               # Collecte logs
│   ├── alertmanager/           # Alerting + règles
│   └── wazuh/                  # SIEM léger
├── security/                   # Sécurité
│   ├── fail2ban/               # Protection brute-force
│   ├── wireguard/              # VPN inter-nodes
│   ├── sealed-secrets/         # Gestion secrets chiffrés
│   └── policies/               # Pod Security Standards
├── backup/                     # Backup & Recovery
│   ├── walg/                   # WAL-G PostgreSQL
│   ├── scripts/                # Scripts backup/restore
│   └── cronjobs/               # CronJobs Kubernetes
├── scripts/                    # Scripts d'automatisation
│   ├── install/                # Installation K3s
│   ├── bootstrap/              # Bootstrap complet
│   ├── testing/                # Tests de charge (k6)
│   ├── disaster-recovery/      # Tests DR
│   ├── compliance/             # Rapports conformité
│   └── utils/                  # Utilitaires
├── apps/                       # Code source applicatif (référence)
│   ├── frontend/               # Dockerfile + config Next.js
│   └── backend/                # Dockerfile + config NestJS
├── argocd/                     # GitOps ArgoCD
│   ├── applications/           # Application manifests
│   └── projects/               # Project definitions
├── .github/
│   └── workflows/              # CI/CD GitHub Actions
└── docs/                       # Documentation
    ├── architecture/           # Diagrammes architecture
    ├── runbooks/               # Runbooks par service
    ├── procedures/             # Procédures incidents
    ├── deployment/             # Guide déploiement
    └── troubleshooting/        # Résolution problèmes
```

## Quickstart

### Prérequis

- [Terraform](https://terraform.io) >= 1.7
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.29
- [Helm](https://helm.sh) >= 3.14
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets) >= 0.25
- [k6](https://k6.io) (tests de charge)
- Compte [Hetzner Cloud](https://console.hetzner.cloud) avec API token
- Clé SSH configurée

### Déploiement rapide

```bash
# 1. Cloner le repository
git clone <repo-url> saas && cd saas

# 2. Configurer les variables
cp terraform/environments/prod/terraform.tfvars.example \
   terraform/environments/prod/terraform.tfvars
# Éditer terraform.tfvars avec vos valeurs

# 3. Provisionner l'infrastructure Hetzner
cd terraform
terraform init
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars

# 4. Installer K3s sur les nodes
cd ../scripts/install
./01-install-k3s-server.sh
./02-install-k3s-agent.sh

# 5. Bootstrap complet (ordre automatique)
cd ../bootstrap
./bootstrap.sh --env production

# 6. Vérifier le déploiement
kubectl get nodes
kubectl get pods --all-namespaces
```

### Vérifications post-déploiement

```bash
# Santé du cluster
kubectl get nodes -o wide
kubectl top nodes

# Santé des services
kubectl get pods -n production
kubectl get pods -n monitoring
kubectl get pods -n security

# Tests de charge
cd scripts/testing
./run-load-test.sh

# Rapport compliance
cd scripts/compliance
./generate-report.sh
```

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture/) | Diagrammes et choix d'architecture |
| [Déploiement](docs/deployment/) | Guide déploiement complet |
| [Runbooks](docs/runbooks/) | Procédures opérationnelles par service |
| [Procédures](docs/procedures/) | Gestion des incidents |
| [Troubleshooting](docs/troubleshooting/) | Résolution des problèmes courants |

## Conformité

Ce projet implémente les contrôles suivants :

- **ISO 27001** : Gestion des accès (RBAC), chiffrement (TLS/secrets), audit (Wazuh), sauvegarde
- **RGPD** : Chiffrement des données, journalisation des accès, droit à l'oubli (scripts)
- **Defense in Depth** : WAF, NetworkPolicies, Pod Security Standards, fail2ban, VPN

## Licence

Projet réalisé dans le cadre de la certification RNCP37680.
