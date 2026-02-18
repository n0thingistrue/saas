# Infrastructure SaaS Securisee Haute Disponibilite

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Kubernetes](https://img.shields.io/badge/K3s-v1.28+-326CE5?logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.10+-EF7B4D?logo=argo&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-v1.7+-7B42BC?logo=terraform&logoColor=white)

**Projet RNCP37680 — Administrateur Systemes, Reseaux et Securite**

Plateforme SaaS production-ready deployee sur 2 nodes Kubernetes (K3s) avec haute disponibilite 99.5%, securite Defense in Depth (7 couches), monitoring complet et deploiement GitOps.

---

## Vue d'ensemble

| | |
|---|---|
| **Fichiers** | ~178 fichiers couvrant infrastructure, applications, monitoring, securite et CI/CD |
| **Architecture** | 2 nodes K3s — Node 1 : 16 vCPU / 32 GB (CCX33) + Node 2 : 4 vCPU / 16 GB (CCX23) |
| **Budget** | ~35 EUR/mois (Hetzner Cloud) |
| **SLA** | 99.5% — RTO < 1 heure, RPO < 15 minutes, 43.8h downtime max/an |
| **Conformite** | ISO 27001 + RGPD |
| **Securite** | Defense in Depth : Firewall → WAF → TLS 1.3 → Rate Limiting → NetworkPolicies → RBAC → Secrets |

---

## Stack technique

### Infrastructure

| Composant | Technologie | Role |
|-----------|------------|------|
| Cloud | Hetzner Cloud (fsn1) | Serveurs, reseau prive, LB, S3, volumes |
| Orchestration | K3s v1.28+ | Cluster Kubernetes leger, certifie CNCF |
| IaC | Terraform v1.7+ | Provisionnement declaratif de toute l'infra |
| GitOps | ArgoCD v2.10+ | Deploiement continu, App of Apps, self-healing |
| CI/CD | GitHub Actions | 6 workflows (build, test, scan, deploy) |
| VPN | WireGuard | Tunnel chiffre inter-nodes (10.0.0.0/24) |

### Bases de donnees

| Composant | Technologie | Role |
|-----------|------------|------|
| Base relationnelle | PostgreSQL 16 + Patroni | Donnees applicatives, failover auto < 30s |
| Cache / Sessions | Redis 7.2 + Sentinel | Cache applicatif, sessions, failover auto < 15s |
| Backup continu | WAL-G → Hetzner S3 | Archivage WAL continu, RPO < 15 min |

### Applications

| Composant | Technologie | Role |
|-----------|------------|------|
| Backend | NestJS 10 (REST + GraphQL) | API, logique metier, 3 replicas HPA (3→6) |
| Frontend | Next.js 14 (SSR) | Interface utilisateur, 2 replicas HPA (2→4) |
| Identites | Samba-AD 4.19 | Active Directory (LDAP + Kerberos + DNS) |

### Ingress et Securite

| Composant | Technologie | Role |
|-----------|------------|------|
| Reverse Proxy | Traefik v3.0 | Routing, TLS termination, 2 replicas |
| WAF | ModSecurity + OWASP CRS 4.0 | Protection OWASP Top 10, Paranoia Level 2 |
| Certificats | cert-manager + Let's Encrypt | TLS 1.3, ECDSA P-256, renouvellement auto |
| Securite reseau | NetworkPolicies | Zero Trust (deny-all + whitelist) |
| Hardening | fail2ban, SealedSecrets, PSS | Anti brute-force, secrets chiffres, Pod Security |

### Monitoring

| Composant | Technologie | Role |
|-----------|------------|------|
| Metriques | Prometheus v2.50 | 9 scrape configs, 7 recording rules, 25+ alertes |
| Dashboards | Grafana 10.4 | 5 dashboards JSON (infra, PG, Redis, apps, Traefik) |
| Logs | Loki 2.9 + Promtail | Logs centralises, retention 15 jours |
| Alerting | AlertManager 0.27 | Routing par severite, Slack + Email + PagerDuty |
| Systeme | Node Exporter | Metriques CPU, memoire, disque, reseau par node |

---

## Architecture

```
Internet
    |
    v
Hetzner Cloud Firewall ─────────── TCP 80/443 uniquement
    |
    v
Hetzner Load Balancer ──────────── TCP passthrough, ProxyProtocol v2
    |
    v
Traefik v3.0 ───────────────────── TLS 1.3, WAF ModSecurity OWASP CRS 4.0
    |
    +──> app.saas.local         ──> Frontend Next.js 14 (SSR)
    +──> api.saas.local         ──> Backend NestJS (REST + GraphQL)
    +──> monitoring.saas.local  ──> Grafana Dashboards
    +──> argocd.saas.local      ──> ArgoCD GitOps UI
    +──> traefik.saas.local     ──> Traefik Dashboard


  Node 1 (CCX33 — 16 vCPU / 32 GB)       Node 2 (CCX23 — 4 vCPU / 16 GB)
  +-------------------------------+       +-------------------------------+
  | K3s Server (Control Plane)    |       | K3s Agent (Worker)            |
  |                               |       |                               |
  | PostgreSQL PRIMARY ◄──────────┼───────┤ PostgreSQL STANDBY            |
  |   Patroni (sync replication)  |       |   Patroni                     |
  |                               |       |                               |
  | Redis MASTER ◄────────────────┼───────┤ Redis REPLICA                 |
  |   Sentinel (quorum 2/3)       |       |   Sentinel                    |
  |                               |       |                               |
  | Backend NestJS   (2/3 pods)   |       | Backend NestJS   (1/3 pods)   |
  | Frontend Next.js (1/2 pods)   |       | Frontend Next.js (1/2 pods)   |
  | Samba-AD (DC, LDAP, DNS)      |       | Traefik          (1/2 pods)   |
  | Traefik          (1/2 pods)   |       | Promtail + Node Exporter      |
  |                               |       |                               |
  | Prometheus + Grafana          |       |                               |
  | Loki + AlertManager           |       |                               |
  | Promtail + Node Exporter      |       |                               |
  +-------------------------------+       +-------------------------------+
              |                                       |
              +──────────── WireGuard VPN ────────────+
                        10.0.0.0/24 chiffre
              |
              v
       Hetzner S3 (Backups WAL-G + Redis RDB)
```

---

## Quickstart

### Prerequis

- Compte [Hetzner Cloud](https://console.hetzner.cloud) avec API token
- [Terraform](https://terraform.io) >= 1.7
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets) >= 0.25
- Cle SSH configuree dans Hetzner Console
- [Git](https://git-scm.com/)

### Deploiement en 5 etapes

**Etape 1 — Cloner le repository**

```bash
git clone https://github.com/your-username/infrastructure-rncp.git
cd infrastructure-rncp
```

**Etape 2 — Provisionner l'infrastructure Hetzner**

```bash
cp terraform/environments/prod/terraform.tfvars.example \
   terraform/environments/prod/terraform.tfvars

# Editer terraform.tfvars avec : hcloud_token, ssh_key_name, location
nano terraform/environments/prod/terraform.tfvars

cd terraform
terraform init
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

**Etape 3 — Installer K3s sur les nodes**

```bash
# Recuperer les IPs depuis les outputs Terraform
export NODE1_IP=$(terraform output -raw node1_ip)
export NODE2_IP=$(terraform output -raw node2_ip)

# Installer K3s server sur Node 1
ssh root@${NODE1_IP} 'bash -s' < scripts/install/01-install-k3s-server.sh

# Recuperer le token et installer K3s agent sur Node 2
ssh root@${NODE2_IP} 'bash -s' < scripts/install/02-install-k3s-agent.sh

# Configurer kubectl local
scp root@${NODE1_IP}:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i "s/127.0.0.1/${NODE1_IP}/g" ~/.kube/config

# Verifier le cluster
kubectl get nodes -o wide
```

**Etape 4 — Deployer via ArgoCD**

```bash
# Installer et configurer ArgoCD
./scripts/argocd/argocd-setup.sh

# Deployer toute l'infrastructure via App of Apps
kubectl apply -f kubernetes/argocd/applications/app-of-apps.yaml

# Suivre le deploiement (sync-waves : databases → samba → backend → frontend → monitoring → ingress)
watch kubectl get applications -n argocd
```

**Etape 5 — Acceder aux services**

```bash
# Verifier que tout fonctionne
kubectl get pods --all-namespaces

# Services disponibles
echo "Frontend   : https://app.saas.local"
echo "Backend    : https://api.saas.local/health"
echo "Grafana    : https://monitoring.saas.local"
echo "ArgoCD     : https://argocd.saas.local"
echo "Traefik    : https://traefik.saas.local"

# Lancer la suite de tests complete
./scripts/tests/run-all-tests.sh
```

---

## Structure du projet

```
infrastructure-rncp/
|
+-- terraform/                          # Infrastructure as Code
|   +-- main.tf                         #   Configuration principale
|   +-- providers.tf                    #   Provider Hetzner + versions
|   +-- variables.tf                    #   Variables globales
|   +-- outputs.tf                      #   Outputs (IPs, IDs)
|   +-- servers.tf                      #   Serveurs cloud (2 nodes)
|   +-- network.tf                      #   Reseau prive + sous-reseaux
|   +-- firewall.tf                     #   Regles firewall Hetzner
|   +-- volumes.tf                      #   Volumes persistants
|   +-- floating-ip.tf                  #   Floating IP HA
|   +-- load-balancer.tf                #   Load Balancer Hetzner
|   +-- s3.tf                           #   Object Storage S3 backups
|   +-- ssh-keys.tf                     #   Cles SSH
|   +-- environments/                   #   Configs par environnement
|   +-- modules/                        #   Modules reutilisables
|
+-- scripts/
|   +-- install/                        # Installation K3s (4 fichiers)
|   +-- bootstrap/                      # Bootstrap orchestration (2 fichiers)
|   +-- argocd/                         # ArgoCD setup + sync (2 fichiers)
|   +-- tests/                          # Tests de validation (9 fichiers)
|       +-- test-failover-postgresql.sh
|       +-- test-failover-redis.sh
|       +-- test-ha-applications.sh
|       +-- test-backup-restore.sh
|       +-- test-load-backend.sh
|       +-- test-security-scan.sh
|       +-- test-monitoring-alerts.sh
|       +-- validate-sla.sh
|       +-- run-all-tests.sh
|
+-- kubernetes/
|   +-- base/                           # Fondations K8s (20 fichiers)
|   |   +-- namespaces/                 #   PSS baseline/restricted
|   |   +-- rbac/                       #   Roles, bindings, service accounts
|   |   +-- network-policies/           #   Zero Trust deny-all + whitelist
|   |   +-- storage/                    #   StorageClass local-storage
|   |   +-- sealed-secrets/             #   Controller bitnami
|   |
|   +-- databases/                      # Bases de donnees HA (18 fichiers)
|   |   +-- postgresql/                 #   Patroni StatefulSet + backup WAL-G
|   |   +-- redis/                      #   Sentinel StatefulSet + persistence
|   |
|   +-- apps/                           # Applications (22 fichiers)
|   |   +-- samba-ad/                   #   Domain Controller AD
|   |   +-- backend/                    #   NestJS Deployment + HPA + ServiceMonitor
|   |   +-- frontend/                   #   Next.js Deployment + HPA + ServiceMonitor
|   |
|   +-- ingress/                        # Ingress et Securite (27 fichiers)
|   |   +-- traefik/                    #   Traefik v3.0 + TLS + dashboard
|   |   +-- cert-manager/              #   Let's Encrypt + ClusterIssuers
|   |   +-- middlewares/                #   Headers, rate-limit, WAF, compress
|   |   +-- routes/                     #   IngressRoutes par service
|   |
|   +-- monitoring/                     # Stack monitoring (28 fichiers)
|   |   +-- prometheus/                 #   StatefulSet + rules + scrape configs
|   |   +-- grafana/                    #   Deployment + 5 dashboards JSON
|   |   +-- loki/                       #   Loki + Promtail DaemonSet
|   |   +-- alertmanager/               #   Routing severite + notifications
|   |   +-- node-exporter/              #   DaemonSet metriques systeme
|   |
|   +-- argocd/                         # GitOps (14 fichiers)
|       +-- applications/               #   App of Apps + 6 applications
|       +-- argocd-configmap.yaml       #   Health checks, OIDC
|       +-- argocd-rbac-configmap.yaml  #   Roles admin/dev/readonly
|       +-- argocd-notifications-configmap.yaml
|
+-- .github/workflows/                 # CI/CD (6 fichiers)
|   +-- ci-backend.yaml                #   Lint, test, scan, build Docker
|   +-- ci-frontend.yaml               #   Lint, test, build, scan, push
|   +-- ci-infrastructure.yaml         #   Validate K8s + Terraform (Checkov)
|   +-- deploy-staging.yaml            #   Deploy auto sur develop
|   +-- deploy-production.yaml         #   Deploy tag v*, approbation manuelle
|   +-- security-scan-scheduled.yaml   #   Scan hebdo (Trivy, npm audit, kubesec)
|
+-- docs/                              # Documentation (12 fichiers)
|   +-- architecture/architecture.md   #   Architecture + choix techniques + DR
|   +-- deployment/deployment.md       #   Guide deploiement 5 phases
|   +-- runbooks/                      #   PostgreSQL, Redis, Traefik
|   +-- procedures/                    #   Gestion des incidents P1-P4
|   +-- cicd.md                        #   Pipelines GitHub Actions
|   +-- gitops.md                      #   Principes GitOps + ArgoCD
|   +-- conformite-rncp.md             #   Couverture 3 blocs + ISO + RGPD
|   +-- procedures-exploitation.md     #   Operations quotidien/hebdo/mensuel
|   +-- troubleshooting-global.md      #   Index consolide 8 composants
|
+-- CHECKLIST-RNCP.md                  # Checklist validation projet
+-- README.md                          # Ce fichier
```

| Dossier | Fichiers | Description |
|---------|----------|-------------|
| `terraform/` | 14 | Infrastructure as Code Hetzner Cloud |
| `scripts/install/` | 4 | Installation K3s (server + agent) |
| `scripts/bootstrap/` | 2 | Bootstrap orchestration |
| `scripts/argocd/` | 2 | Setup et sync ArgoCD |
| `scripts/tests/` | 9 | Tests failover, charge, securite, SLA |
| `kubernetes/base/` | 20 | Namespaces, RBAC, NetworkPolicies, Storage |
| `kubernetes/databases/` | 18 | PostgreSQL Patroni + Redis Sentinel + Backups |
| `kubernetes/apps/` | 22 | Samba-AD + Backend NestJS + Frontend Next.js |
| `kubernetes/ingress/` | 27 | Traefik + cert-manager + WAF + Middlewares |
| `kubernetes/monitoring/` | 28 | Prometheus + Grafana (5 dashboards) + Loki + AlertManager |
| `kubernetes/argocd/` | 14 | ArgoCD + App of Apps (6 Applications) |
| `.github/workflows/` | 6 | CI/CD pipelines |
| `docs/` | 12 | Architecture, runbooks, procedures, conformite |
| **Total** | **~178** | |

---

## Tests et Validation

### Executer tous les tests

```bash
# Suite complete (8 tests)
./scripts/tests/run-all-tests.sh

# Mode rapide (securite + monitoring + SLA)
./scripts/tests/run-all-tests.sh --quick

# Generer un rapport fichier
./scripts/tests/run-all-tests.sh --report

# Simulation sans action reelle
./scripts/tests/run-all-tests.sh --dry-run
```

### Tests individuels

| Test | Script | Objectif | Metrique |
|------|--------|----------|----------|
| Failover PostgreSQL | `test-failover-postgresql.sh` | Patroni switchover + integrite donnees | RTO < 30s |
| Failover Redis | `test-failover-redis.sh` | Sentinel failover + RPO = 0 | RTO < 15s |
| HA Applications | `test-ha-applications.sh` | Rolling restart zero-downtime | 0 requete perdue |
| Backup / Restore | `test-backup-restore.sh` | WAL-G backup + verify + retention | RPO < 15 min |
| Charge Backend | `test-load-backend.sh` | Performance sous charge + autoscaling | p95 < 500ms, > 500 req/s |
| Securite | `test-security-scan.sh` | PSS, RBAC, TLS, NetworkPolicies, Trivy | 0 vulns CRITICAL |
| Monitoring | `test-monitoring-alerts.sh` | Targets, regles, Grafana, Loki, AlertManager | Detection < 2 min |
| SLA | `validate-sla.sh` | Uptime par service + SLA global | >= 99.5% |

### Rapport attendu

```
  Test                           Resultat   Duree
  1_pg_failover                  PASS         25s
  2_redis_failover               PASS         12s
  3_ha_apps                      PASS         68s
  4_backup                       PASS         45s
  5_load                         PASS         35s
  6_security                     PASS         20s
  7_monitoring                   PASS         15s
  8_sla                          PASS         10s

  Total    : 8
  Passed   : 8
  Failed   : 0

  VALIDATION REUSSIE
```

---

## Couverture RNCP37680

| Bloc | Competences | Implementation |
|------|-------------|---------------|
| **BC01** — Administration infrastructures securisees | Reseau, firewall, VPN, identites, chiffrement | K3s 2 nodes, Hetzner Firewall, WireGuard, Samba-AD (LDAP/Kerberos), NetworkPolicies Zero Trust, SealedSecrets, RBAC |
| **BC02** — Conception et mise en oeuvre solutions | HA, monitoring, GitOps, IaC, CI/CD | Patroni + Sentinel failover, Prometheus 25+ alertes, Grafana 5 dashboards, ArgoCD App of Apps, Terraform, 6 GitHub Actions, HPA autoscaling |
| **BC03** — Gestion cybersecurite | WAF, RBAC, scans, PRA/PCA, conformite | Defense in Depth 7 couches, WAF ModSecurity CRS 4.0, TLS 1.3, Trivy/Checkov/Kubesec scans, backup WAL-G, incidents P1-P4, ISO 27001, RGPD |

> Documentation complete : [docs/conformite-rncp.md](docs/conformite-rncp.md)

---

## Couts mensuels

| Ressource | Specifications | Cout/mois |
|-----------|---------------|-----------|
| Node 1 (CCX33) | 16 vCPU, 32 GB RAM, 320 GB SSD | Paye |
| Node 2 (CCX23) | 4 vCPU, 16 GB RAM, 160 GB SSD | ~24.49 EUR |
| S3 Hetzner | Backups WAL-G + Redis RDB | ~5 EUR |
| Backblaze B2 | Backup offsite (replication S3) | ~5 EUR |
| Domaine | DNS (optionnel) | ~1 EUR |
| **Total** | | **~35 EUR/mois** |

> Floating IP et Load Balancer inclus dans le forfait Node 1. Volumes persistants inclus dans les serveurs.

---

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture complete](docs/architecture/architecture.md) | Diagrammes Mermaid, choix techniques justifies, Defense in Depth, HA, Disaster Recovery, evolutions |
| [Guide de deploiement](docs/deployment/deployment.md) | Deploiement complet en 5 phases |
| [CI/CD](docs/cicd.md) | 6 workflows GitHub Actions, secrets, environments, procedures release |
| [GitOps](docs/gitops.md) | 4 principes GitOps, App of Apps, gestion secrets, multi-env |
| [Conformite RNCP](docs/conformite-rncp.md) | Couverture 3 blocs BC01/BC02/BC03, ISO 27001, RGPD |
| [Procedures d'exploitation](docs/procedures-exploitation.md) | Operations quotidien, hebdo, mensuel, trimestriel, urgences |
| [Troubleshooting global](docs/troubleshooting-global.md) | Index consolide 8 composants, arbre de decision, escalade |
| [Runbook PostgreSQL](docs/runbooks/postgresql.md) | Patroni failover, WAL-G backup/restore, PITR |
| [Runbook Redis](docs/runbooks/redis.md) | Sentinel failover, persistence AOF/RDB |
| [Runbook Traefik](docs/runbooks/traefik.md) | TLS, middlewares, routing, WAF |
| [Gestion des incidents](docs/procedures/incident-management.md) | Classification P1-P4, triage, escalade, post-mortem |
| [Checklist RNCP](CHECKLIST-RNCP.md) | Checklist de validation complete du projet |

---

## Troubleshooting rapide

### Nodes NotReady

```bash
kubectl get nodes
systemctl status k3s          # Node 1
systemctl status k3s-agent    # Node 2
wg show                       # Verifier WireGuard
```

### Pods CrashLoopBackOff

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
# Causes frequentes : ConfigMap invalide, DB inaccessible, secret manquant
```

### ArgoCD Application OutOfSync

```bash
argocd app get <app-name>
argocd app diff <app-name>
argocd app sync <app-name> --force
```

### Certificats TLS non emis

```bash
kubectl get certificates --all-namespaces
kubectl describe certificate <name> -n ingress
kubectl logs -n cert-manager -l app=cert-manager
kubectl get challenges -n ingress
```

### Alertes Prometheus non declenchees

```bash
# Verifier les targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Acceder http://localhost:9090/targets

# Verifier les regles
kubectl get configmap prometheus-rules -n monitoring -o yaml

# Verifier AlertManager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Acceder http://localhost:9093/#/alerts
```

### PostgreSQL replication cassee

```bash
kubectl exec -n production postgresql-0 -- patronictl list
kubectl exec -n production postgresql-0 -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"
# Si necessaire : patronictl reinit <standby-name>
```

> Documentation complete : [docs/troubleshooting-global.md](docs/troubleshooting-global.md)

---

## Contribution

```bash
# 1. Fork le repository
# 2. Creer une branche
git checkout -b feature/ma-feature develop

# 3. Developper + tester
./scripts/tests/run-all-tests.sh --dry-run

# 4. Committer (Conventional Commits)
git commit -m "feat(backend): add user management endpoint"

# 5. Pousser et creer une Pull Request
git push origin feature/ma-feature
```

### Conventions

- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
- **Branches** : `feature/*`, `fix/*`, `hotfix/*` depuis `develop`
- **CI obligatoire** : lint + tests + security scan doivent passer avant merge
- **Code review** : 1 approbation minimum pour merge sur `main`

---

## Licence

MIT License — Projet realise dans le cadre de la certification RNCP37680.

Voir le fichier [LICENSE](LICENSE) pour les details.

---

## Auteur

**Projet RNCP37680 — Administrateur Systemes, Reseaux et Securite**

Fevrier 2026

---

> **Checklist de validation** : Voir [CHECKLIST-RNCP.md](CHECKLIST-RNCP.md) pour la checklist complete du projet.
>
> **Conformite RNCP** : Voir [docs/conformite-rncp.md](docs/conformite-rncp.md) pour le detail des 3 blocs de competences.
