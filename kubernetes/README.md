# Kubernetes Manifests

## Vue d'ensemble

Manifests Kubernetes pour le déploiement de la stack SaaS complète sur K3s.
Organisation en base + overlays (Kustomize) pour gérer prod/staging.

## Structure

```
kubernetes/
├── base/                       # Ressources de base communes
│   ├── namespaces/             # Namespaces (production, staging, monitoring, security)
│   ├── rbac/                   # Roles, ClusterRoles, Bindings
│   ├── network-policies/       # Isolation réseau entre namespaces
│   └── pod-security/           # Pod Security Standards (restricted)
├── apps/                       # Déploiements applicatifs
│   ├── frontend/               # Next.js SSR (Deployment + HPA + Service)
│   ├── backend/                # NestJS (Deployment + HPA + Service)
│   ├── postgresql/             # PostgreSQL Patroni (StatefulSet HA)
│   ├── redis/                  # Redis Sentinel (StatefulSet HA)
│   └── samba-ad/               # Samba-AD (StatefulSet + PV)
├── ingress/                    # Ingress et TLS
│   ├── traefik/                # Traefik IngressRoutes + middleware
│   ├── cert-manager/           # Let's Encrypt certificates
│   └── waf/                    # ModSecurity WAF rules
├── secrets/                    # SealedSecrets (chiffrés, safe to commit)
└── overlays/                   # Kustomize overlays
    ├── production/             # Production overrides
    └── staging/                # Staging overrides
```

## Namespaces

| Namespace | Usage |
|-----------|-------|
| `production` | Services applicatifs (frontend, backend, DB, cache) |
| `staging` | Environnement de test (on-demand sur Node 2) |
| `monitoring` | Prometheus, Grafana, Loki, AlertManager |
| `security` | Wazuh, sealed-secrets-controller |
| `ingress` | Traefik, cert-manager |
| `argocd` | ArgoCD GitOps controller |

## Répartition Nodes

Les pods sont répartis via `nodeAffinity` et `podAntiAffinity` :

- **Node 1 (32GB)** : Workloads principaux (DB primary, backends majoritaires, monitoring)
- **Node 2 (16GB)** : Replicas HA (DB standby, 1 backend, security, staging)

## Ordre de déploiement

1. Namespaces + RBAC + Pod Security
2. Network Policies
3. Sealed Secrets controller
4. Cert-manager + ClusterIssuers
5. Traefik + WAF
6. PostgreSQL Patroni
7. Redis Sentinel
8. Samba-AD
9. Backend NestJS
10. Frontend Next.js
11. Monitoring stack
12. Wazuh agent
13. ArgoCD

## Commandes utiles

```bash
# Appliquer les bases
kubectl apply -k kubernetes/base/

# Déployer une app
kubectl apply -k kubernetes/apps/postgresql/

# Overlay production
kubectl apply -k kubernetes/overlays/production/

# Vérifier les ressources par namespace
kubectl get all -n production
kubectl top pods -n production
```
