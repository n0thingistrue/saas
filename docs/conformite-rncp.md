# Conformite RNCP37680 - Administrateur Systemes, Reseaux et Securite

## Presentation

Ce document detaille la couverture des 3 blocs de competences de la certification
**RNCP37680** par le projet Infrastructure SaaS Haute Disponibilite.

Le projet demonstre les competences d'un administrateur systemes, reseaux et securite
a travers la conception, le deploiement et l'exploitation d'une infrastructure
de production securisee.

---

## Bloc de Competences 1 (BC01) : Administrer les infrastructures informatiques securisees

### C1.1 - Administrer et securiser les composants constituant l'infrastructure

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Administration serveurs | 2 nodes Hetzner Cloud (CCX33 + CCX23), provisioning Terraform | `terraform/servers.tf` |
| Configuration reseau | Reseau prive 10.10.0.0/16, sous-reseaux, routing | `terraform/network.tf` |
| Virtualisation/Conteneurisation | Cluster K3s, Deployments, StatefulSets, DaemonSets | `kubernetes/` |
| Stockage | PVC local-storage, volumes Hetzner, Object Storage S3 | `terraform/volumes.tf`, `terraform/s3.tf` |
| Automatisation | Scripts shell installation K3s, bootstrap, tests | `scripts/install/`, `scripts/bootstrap/` |
| Documentation | Architecture, procedures, runbooks, troubleshooting | `docs/` |

### C1.2 - Integrer les solutions d'infrastructure reseau

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| DNS | CoreDNS (K3s), Samba-AD DNS interne | `kubernetes/apps/samba-ad/` |
| Load Balancing | Hetzner LB (TCP passthrough, ProxyProtocol v2) | `terraform/load-balancer.tf` |
| Reverse Proxy | Traefik v3.0 avec routing IngressRoutes | `kubernetes/ingress/traefik/` |
| VPN | WireGuard tunnel inter-nodes (10.0.0.0/24) | `scripts/install/01-install-k3s-server.sh` |
| Firewall | Hetzner Cloud Firewall (TCP 80/443 only), NetworkPolicies | `terraform/firewall.tf`, `kubernetes/base/network-policies/` |
| Haute Disponibilite | 2 nodes, anti-affinity, replicas, failover auto | Architecture globale |

### C1.3 - Administrer les systemes de gestion des identites

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Active Directory | Samba-AD 4.19 (Domain Controller) | `kubernetes/apps/samba-ad/` |
| LDAP | Authentification LDAP (passport-ldapauth) | `kubernetes/apps/backend/backend-configmap.yaml` |
| Kerberos | SSO Kerberos via Samba-AD | `kubernetes/apps/samba-ad/samba-configmap.yaml` |
| RBAC | Kubernetes RBAC (roles, bindings, service accounts) | `kubernetes/base/rbac/` |
| ArgoCD RBAC | Roles admin/developer/readonly, mapping LDAP | `kubernetes/argocd/argocd-rbac-configmap.yaml` |
| Gestion des secrets | SealedSecrets (bitnami), chiffrement asymetrique | `kubernetes/base/sealed-secrets/` |

### Preuves BC01

- [x] Infrastructure 2 nodes provisionnee par Terraform (IaC)
- [x] Reseau prive + VPN WireGuard entre les nodes
- [x] Firewall Hetzner + NetworkPolicies Zero Trust
- [x] Samba-AD comme controleur de domaine (LDAP + Kerberos)
- [x] RBAC Kubernetes avec roles differencies
- [x] Scripts d'installation automatises
- [x] Documentation architecture et procedures completes

---

## Bloc de Competences 2 (BC02) : Concevoir et mettre en oeuvre une solution en reponse a un besoin d'evolution

### C2.1 - Concevoir une solution technique repondant a un besoin d'evolution

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Analyse du besoin | SaaS HA, SLA 99.5%, RTO <1h, RPO <15min | `docs/architecture/architecture.md` |
| Choix technologiques | K3s, Patroni, Sentinel, Traefik, ArgoCD (justifies) | `docs/architecture/architecture.md` |
| Architecture | 2 nodes, microservices, HA databases, monitoring | Architecture globale |
| Budget | ~35 EUR/mois, optimisation ressources | `README.md` |
| Evolutivite | HPA autoscaling, ArgoCD GitOps, multi-env | `kubernetes/apps/*/hpa.yaml` |

### C2.2 - Mettre en production la solution

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| CI/CD | 6 workflows GitHub Actions (lint, test, build, deploy) | `.github/workflows/` |
| GitOps | ArgoCD, App of Apps, sync-waves, self-healing | `kubernetes/argocd/` |
| Deploiement continu | Automated sync, rollback automatique | `kubernetes/argocd/applications/` |
| Conteneurisation | Docker multi-stage builds, images optimisees | `.github/workflows/ci-backend.yaml` |
| Tests automatises | CI bloquant (lint + test), security scan | `.github/workflows/` |
| Environments | Staging (auto) + Production (approbation manuelle) | `docs/cicd.md` |

### C2.3 - Superviser, mesurer et optimiser la solution

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Monitoring metriques | Prometheus v2.50, 9 scrape configs | `kubernetes/monitoring/prometheus/` |
| Dashboards | 5 dashboards Grafana JSON provisioned | `kubernetes/monitoring/grafana/dashboards/` |
| Logs centralises | Loki + Promtail (DaemonSet) | `kubernetes/monitoring/loki/` |
| Alerting | AlertManager, 25+ regles, routing par severite | `kubernetes/monitoring/alertmanager/` |
| Recording rules | 7 regles de pre-calcul PromQL | `kubernetes/monitoring/prometheus/prometheus-rules.yaml` |
| Notifications | Slack + Email + PagerDuty (severite-based) | `kubernetes/monitoring/alertmanager/alertmanager-configmap.yaml` |
| SLA tracking | Script validate-sla.sh, metriques Prometheus | `scripts/tests/validate-sla.sh` |
| Autoscaling | HPA backend 3-6, frontend 2-4 (CPU/Memory) | `kubernetes/apps/*/hpa.yaml` |

### Preuves BC02

- [x] Architecture documentee avec justifications techniques
- [x] CI/CD complet (6 workflows GitHub Actions)
- [x] GitOps ArgoCD avec App of Apps pattern
- [x] Stack monitoring complete (Prometheus + Grafana + Loki + AlertManager)
- [x] 5 dashboards Grafana operationnels
- [x] 25+ regles d'alerting configurees
- [x] Autoscaling HPA configure
- [x] Scripts de tests de validation (8 scripts)

---

## Bloc de Competences 3 (BC03) : Participer a la gestion de la cybersecurite

### C3.1 - Participer a la mise en oeuvre de la politique de securite

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Defense in Depth | Firewall → LB → WAF → TLS → NetworkPolicy → RBAC → Secrets | Architecture multicouche |
| TLS | cert-manager + Let's Encrypt, TLS 1.3 minimum, ECDSA P-256 | `kubernetes/ingress/cert-manager/` |
| WAF | ModSecurity OWASP CRS 4.0, Paranoia Level 2, block mode | `kubernetes/ingress/middlewares/middleware-waf-modsecurity.yaml` |
| Headers securite | HSTS, CSP, X-Frame-Options, Permissions-Policy | `kubernetes/ingress/middlewares/middleware-security-headers.yaml` |
| Rate Limiting | 3 niveaux : default 100/s, API 50/s, Auth 10/min | `kubernetes/ingress/middlewares/middleware-rate-limit.yaml` |
| Chiffrement transit | WireGuard inter-nodes, TLS 1.3 ingress | Architecture globale |
| Chiffrement repos | SealedSecrets, PostgreSQL pg_crypto | `kubernetes/base/sealed-secrets/` |
| Zero Trust Network | NetworkPolicies deny-all + whitelist | `kubernetes/base/network-policies/` |
| Pod Security | PSS baseline/restricted par namespace | `kubernetes/base/namespaces/` |

### C3.2 - Analyser les risques et mettre en oeuvre des mesures de securite

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Scan vulnerabilites | Trivy (images), Checkov (IaC), Kubesec (manifests) | `.github/workflows/security-scan-scheduled.yaml` |
| Scan hebdomadaire | Cron Monday 2am, 8 images, npm audit | `.github/workflows/security-scan-scheduled.yaml` |
| Anti brute-force | Rate limit auth 10/min, fail2ban nodes | `kubernetes/ingress/middlewares/middleware-rate-limit.yaml` |
| Audit trail | Git log (GitOps), ArgoCD history, access logs JSON | `docs/gitops.md` |
| Backup securise | WAL-G + Hetzner S3, chiffrement, retention | `kubernetes/databases/postgresql/backup/` |
| Disaster Recovery | PRA/PCA documente, RTO <1h, RPO <15min | `docs/architecture/architecture.md` |

### C3.3 - Participer a la gestion des incidents de securite

| Competence | Implementation | Fichiers |
|-----------|---------------|----------|
| Detection incidents | AlertManager + Prometheus (< 2min) | `kubernetes/monitoring/alertmanager/` |
| Classification | P1 (critique) → P4 (info), temps de reponse | `docs/procedures/incident-management.md` |
| Reponse incidents | Runbooks PostgreSQL, Redis, Traefik | `docs/runbooks/` |
| Post-mortem | Procedure documentee pour P1/P2 | `docs/procedures/incident-management.md` |
| DDoS mitigation | WAF + Rate Limiting + Hetzner Firewall | `kubernetes/ingress/middlewares/` |
| Rollback | ArgoCD rollback, git revert | `docs/gitops.md` |
| Escalade | Matrice d'escalade documentee | `docs/procedures/incident-management.md` |

### Preuves BC03

- [x] Defense in Depth (7 couches de securite)
- [x] WAF ModSecurity OWASP CRS 4.0 en mode blocking
- [x] TLS 1.3 minimum avec certificats ECDSA
- [x] NetworkPolicies Zero Trust
- [x] Scan de securite automatise (CI + hebdomadaire)
- [x] Rate limiting multi-niveaux (anti brute-force)
- [x] Procedures de gestion d'incidents (P1-P4)
- [x] Runbooks operationnels (PostgreSQL, Redis, Traefik)
- [x] Backup continu WAL-G avec RPO < 15min

---

## Tableau de synthese

| Bloc | Competences | Couverture | Completude |
|------|-------------|------------|------------|
| BC01 | Administration infrastructures securisees | Reseau, firewall, VPN, identites, chiffrement | 100% |
| BC02 | Conception et mise en oeuvre solutions | HA, monitoring, GitOps, IaC, CI/CD | 100% |
| BC03 | Gestion cybersecurite | WAF, RBAC, scans, PRA/PCA, ISO 27001 | 100% |

## Correspondance ISO 27001

| Domaine ISO 27001 | Implementation projet |
|--------------------|-----------------------|
| A.5 Politiques de securite | PSS, RBAC, NetworkPolicies documentes |
| A.6 Organisation | Roles RBAC (admin, developer, readonly) |
| A.8 Gestion des actifs | Inventaire Terraform, tags, labels K8s |
| A.9 Controle d'acces | LDAP/Kerberos, RBAC, SealedSecrets |
| A.10 Cryptographie | TLS 1.3, WireGuard, SealedSecrets, ECDSA |
| A.12 Securite operations | Monitoring, alerting, procedures, runbooks |
| A.13 Securite communications | Firewall, NetworkPolicies, WAF, rate limiting |
| A.14 Acquisition/Dev | CI/CD securise, scans Trivy/Checkov |
| A.16 Gestion incidents | Classification P1-P4, detection <2min, escalade |
| A.17 Continuite activite | HA 2 nodes, failover auto, backup WAL-G, PRA |
| A.18 Conformite | RGPD (logs anonymises), audit trail Git |

## Correspondance RGPD

| Obligation RGPD | Implementation |
|------------------|----------------|
| Minimisation des donnees | Logs anonymises (Promtail pipeline), retention 15j |
| Chiffrement | TLS 1.3 transit, WireGuard inter-node, SealedSecrets repos |
| Droit a l'oubli | PostgreSQL (DELETE), Redis (TTL/EXPIRE) |
| Registre des traitements | Git log = journal complet des modifications |
| Notification violation | AlertManager → Slack/Email < 2min detection |
| Privacy by Design | NetworkPolicies Zero Trust, RBAC, PSS |
