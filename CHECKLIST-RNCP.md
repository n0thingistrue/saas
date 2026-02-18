# CHECKLIST RNCP37680 - Validation du projet

## Informations projet

- **Certification** : RNCP37680 - Administrateur Systemes, Reseaux et Securite
- **Projet** : Infrastructure SaaS Haute Disponibilite
- **Infrastructure** : 2 nodes K3s sur Hetzner Cloud
- **Budget** : ~35 EUR/mois
- **SLA cible** : 99.5%

---

## 1. Infrastructure (Terraform)

- [x] Provisionnement IaC avec Terraform >= 1.7
- [x] 2 serveurs Hetzner Cloud (CCX33 + CCX23)
- [x] Reseau prive isole (10.10.0.0/16)
- [x] Floating IP pour haute disponibilite
- [x] Load Balancer Hetzner (TCP passthrough, ProxyProtocol v2)
- [x] Volumes persistants pour donnees
- [x] Object Storage S3 pour backups WAL-G
- [x] Firewall Hetzner (TCP 80/443 uniquement)
- [x] Cles SSH configurees
- [x] Fichiers : `terraform/` (14 fichiers)

## 2. Installation K3s

- [x] Script installation K3s server (Node 1)
- [x] Script installation K3s agent (Node 2)
- [x] WireGuard VPN inter-nodes (10.0.0.0/24)
- [x] Configuration kubectl
- [x] Fichiers : `scripts/install/` (4 fichiers)

## 3. Base Kubernetes

- [x] Namespaces avec Pod Security Standards (baseline/restricted)
- [x] RBAC : roles admin, developer, readonly
- [x] NetworkPolicies Zero Trust (deny-all + whitelist)
- [x] StorageClass local-storage
- [x] ResourceQuotas par namespace
- [x] LimitRanges par namespace
- [x] SealedSecrets controller (bitnami)
- [x] Fichiers : `kubernetes/base/` (20 fichiers)

## 4. Bases de donnees HA

### PostgreSQL + Patroni
- [x] StatefulSet 2 replicas (Primary + Standby)
- [x] Patroni failover automatique (RTO < 30s)
- [x] Streaming replication synchrone
- [x] WAL-G backup continu vers S3
- [x] CronJob backup quotidien
- [x] PVC 50GB local-storage
- [x] ServiceMonitor + alertes Prometheus
- [x] Strict podAntiAffinity (1 pod par node)

### Redis Sentinel
- [x] StatefulSet 2 replicas (Master + Replica)
- [x] 3 Sentinels (quorum 2/3)
- [x] Failover automatique (RTO < 15s)
- [x] Persistence AOF + RDB
- [x] maxmemory 1GB + allkeys-lru
- [x] ServiceMonitor + alertes Prometheus
- [x] Strict podAntiAffinity

- [x] Fichiers : `kubernetes/databases/` (18 fichiers)

## 5. Applications

### Samba-AD (Active Directory)
- [x] Domain Controller (LDAP + Kerberos + DNS)
- [x] StatefulSet avec PVC 20GB
- [x] Configuration domaine saas.local
- [x] Groupes : Admins, Developers, Operators, ReadOnly
- [x] Integration LDAP pour backend NestJS
- [x] PodMonitor Prometheus

### Backend NestJS
- [x] Deployment 3 replicas
- [x] REST + GraphQL API
- [x] Authentification LDAP (passport-ldapauth)
- [x] JWT tokens (access + refresh)
- [x] Connexion PostgreSQL + Redis
- [x] Health checks (/health)
- [x] HPA 3-6 replicas (CPU > 70%, Memory > 80%)
- [x] ServiceMonitor + 7 alertes
- [x] Preferred podAntiAffinity

### Frontend Next.js 14
- [x] Deployment 2 replicas
- [x] SSR (Server-Side Rendering)
- [x] Port 3001
- [x] HPA 2-4 replicas
- [x] ServiceMonitor + 5 alertes
- [x] readOnlyRootFilesystem
- [x] Preferred podAntiAffinity

- [x] Fichiers : `kubernetes/apps/` (22 fichiers)

## 6. Ingress et Securite

### Traefik v3.0
- [x] Deployment 2 replicas
- [x] Strict podAntiAffinity
- [x] EntryPoints : web (80), websecure (443), metrics (9100)
- [x] ProxyProtocol v2 (Hetzner LB)
- [x] Access logs JSON
- [x] Metriques Prometheus
- [x] Dashboard securise (BasicAuth + IngressRoute)
- [x] TLSOption TLS 1.3 minimum
- [x] ServiceMonitor + 7 alertes

### cert-manager
- [x] Deployment controller + webhook + cainjector
- [x] ClusterIssuer Let's Encrypt (prod + staging)
- [x] HTTP-01 challenge solver via Traefik
- [x] 4 certificats ECDSA P-256
- [x] Renouvellement automatique (renewBefore 720h)

### Middlewares securite
- [x] Security Headers (HSTS, CSP, X-Frame-Options, Permissions-Policy)
- [x] Rate Limiting 3 niveaux (100/s, 50/s, 10/min auth)
- [x] Compression gzip/brotli
- [x] Redirect HTTPS (301)
- [x] WAF ModSecurity OWASP CRS 4.0 (Paranoia Level 2, block mode)
- [x] IP Whitelist admin

### IngressRoutes
- [x] Frontend (app.saas.local)
- [x] Backend API (api.saas.local) avec WAF
- [x] Grafana (monitoring.saas.local)
- [x] ArgoCD (argocd.saas.local)
- [x] Route auth avec rate-limit strict (priority 100)

### NetworkPolicies Ingress
- [x] Traefik → Frontend :3001
- [x] Traefik → Backend :3000
- [x] Traefik → ModSecurity :8080
- [x] ACME egress (cert-manager)

- [x] Fichiers : `kubernetes/ingress/` (27 fichiers)

## 7. Monitoring

### Prometheus
- [x] StatefulSet 1 replica avec PVC 15GB
- [x] 9 scrape configs
- [x] 7 recording rules (pre-calcul PromQL)
- [x] 25+ alerting rules (5 groupes)
- [x] Retention 15 jours + 14GB taille max

### Grafana
- [x] Deployment 1 replica
- [x] 2 datasources (Prometheus + Loki)
- [x] 5 dashboards JSON provisioned :
  - [x] Infrastructure (CPU, Memory, Disk, Network)
  - [x] PostgreSQL (connections, replication, cache hit)
  - [x] Redis (memory, hit rate, commands/s)
  - [x] Applications (backend + frontend metriques)
  - [x] Traefik (requests, errors, certificates)

### Loki + Promtail
- [x] Loki StatefulSet avec PVC 10GB
- [x] Schema v13 TSDB, retention 15 jours
- [x] Promtail DaemonSet (tous les nodes)
- [x] Pipeline JSON parsing
- [x] Filtrage logs bruit (healthcheck, metrics)

### AlertManager
- [x] Routing par severite (critical 1h, warning 4h, info 24h)
- [x] 4 receivers (default, critical, warning, info)
- [x] Notifications Slack + Email + PagerDuty
- [x] Templates Slack personnalises
- [x] Inhibit rules

### Node Exporter
- [x] DaemonSet sur tous les nodes
- [x] Metriques systeme (CPU, memory, disk, network)

- [x] Fichiers : `kubernetes/monitoring/` (28 fichiers)

## 8. GitOps (ArgoCD)

- [x] ArgoCD installe (namespace argocd)
- [x] ConfigMap personnalise (health checks Lua, OIDC placeholder)
- [x] RBAC 3 roles (admin, developer, readonly)
- [x] Notifications Slack (4 triggers, 4 templates)
- [x] IngressRoute securise (argocd.saas.local)
- [x] App of Apps pattern
- [x] 6 Applications avec sync-waves :
  - [x] Wave 0 : databases (automated)
  - [x] Wave 1 : samba-ad (MANUAL)
  - [x] Wave 2 : backend (automated)
  - [x] Wave 3 : frontend (automated)
  - [x] Wave 4 : monitoring (automated)
  - [x] Wave 5 : ingress (automated)
- [x] Self-healing + prune actives
- [x] Retry policy (limit 5, exponential backoff)
- [x] Fichiers : `kubernetes/argocd/` (14 fichiers)

## 9. CI/CD (GitHub Actions)

- [x] ci-backend.yaml : lint, test, security scan, build Docker, notify
- [x] ci-frontend.yaml : lint, test, build, security scan, push, notify
- [x] ci-infrastructure.yaml : validate K8s (kustomize, Checkov), validate Terraform
- [x] deploy-staging.yaml : deploy automatique sur develop
- [x] deploy-production.yaml : tag v*, approbation manuelle, smoke tests
- [x] security-scan-scheduled.yaml : cron lundi 2h, Trivy 8 images, npm audit, kubesec
- [x] Fichiers : `.github/workflows/` (6 fichiers)

## 10. Scripts de tests

- [x] test-failover-postgresql.sh (RTO < 30s)
- [x] test-failover-redis.sh (RTO < 15s)
- [x] test-ha-applications.sh (zero downtime)
- [x] test-backup-restore.sh (RPO < 15min, RTO < 1h)
- [x] test-load-backend.sh (p95 < 500ms, > 500 req/s)
- [x] test-security-scan.sh (0 CRITICAL)
- [x] test-monitoring-alerts.sh (detection < 2min)
- [x] validate-sla.sh (>= 99.5%)
- [x] run-all-tests.sh (orchestrateur)
- [x] Fichiers : `scripts/tests/` (9 fichiers)

## 11. Documentation

- [x] README.md principal (badges, architecture, quickstart)
- [x] Architecture detaillee (Mermaid, choix techniques, DR, evolutions)
- [x] Guide de deploiement (5 phases)
- [x] CI/CD (workflows, secrets, procedures)
- [x] GitOps (principes, App of Apps, secrets, multi-env)
- [x] Conformite RNCP (3 blocs, ISO 27001, RGPD)
- [x] Procedures d'exploitation (quotidien, hebdo, mensuel, trimestriel)
- [x] Troubleshooting global (index consolide, arbre de decision)
- [x] Runbook PostgreSQL (failover, backup, restore)
- [x] Runbook Redis (sentinel, persistence)
- [x] Runbook Traefik (TLS, middlewares, routing)
- [x] Gestion des incidents (P1-P4, escalade, post-mortem)
- [x] Fichiers : `docs/` (12 fichiers)

---

## Metriques cibles

| Metrique | Cible | Mecanisme de validation |
|----------|-------|------------------------|
| SLA | >= 99.5% | `validate-sla.sh` |
| RTO PostgreSQL | < 30s | `test-failover-postgresql.sh` |
| RTO Redis | < 15s | `test-failover-redis.sh` |
| RPO | < 15 min | `test-backup-restore.sh` |
| Latence p95 | < 500ms | `test-load-backend.sh` |
| Debit | > 500 req/s | `test-load-backend.sh` |
| Vulnerabilites CRITICAL | 0 | `test-security-scan.sh` |
| Detection anomalie | < 2 min | `test-monitoring-alerts.sh` |
| Zero downtime | 0 requete perdue | `test-ha-applications.sh` |

---

## Recapitulatif fichiers

| Dossier | Fichiers | Status |
|---------|----------|--------|
| `terraform/` | 14 | Complet |
| `scripts/install/` | 4 | Complet |
| `scripts/bootstrap/` | 2 | Complet |
| `scripts/argocd/` | 2 | Complet |
| `scripts/tests/` | 9 | Complet |
| `kubernetes/base/` | 20 | Complet |
| `kubernetes/databases/` | 18 | Complet |
| `kubernetes/apps/` | 22 | Complet |
| `kubernetes/ingress/` | 27 | Complet |
| `kubernetes/monitoring/` | 28 | Complet |
| `kubernetes/argocd/` | 14 | Complet |
| `.github/workflows/` | 6 | Complet |
| `docs/` | 12 | Complet |
| **TOTAL** | **~178** | **Complet** |

---

## Couverture RNCP37680

| Bloc | Description | Couverture |
|------|-------------|------------|
| BC01 | Administration infrastructures securisees | 100% |
| BC02 | Conception et mise en oeuvre solutions | 100% |
| BC03 | Gestion cybersecurite | 100% |

Detail complet : [docs/conformite-rncp.md](docs/conformite-rncp.md)

---

## Validation finale

- [ ] Terraform apply reussi (2 nodes, reseau, volumes, LB, S3)
- [ ] K3s cluster operationnel (2 nodes Ready)
- [ ] ArgoCD deploye et App of Apps appliquee
- [ ] Tous les pods Running dans tous les namespaces
- [ ] Frontend accessible (https://app.saas.local)
- [ ] Backend API accessible (https://api.saas.local/health)
- [ ] Grafana accessible (https://monitoring.saas.local)
- [ ] ArgoCD accessible (https://argocd.saas.local)
- [ ] PostgreSQL replication fonctionnelle (Patroni list)
- [ ] Redis replication fonctionnelle (INFO replication)
- [ ] Certificats TLS valides (cert-manager)
- [ ] WAF ModSecurity operationnel
- [ ] Alertes configurees et testees
- [ ] Backups WAL-G fonctionnels
- [ ] `./scripts/tests/run-all-tests.sh` → TOUS PASSES
