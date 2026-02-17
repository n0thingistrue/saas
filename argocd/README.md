# ArgoCD - GitOps

## Vue d'ensemble

ArgoCD gère le déploiement continu via GitOps :
- Synchronisation automatique du cluster avec le repository Git
- Détection de drift (écart entre état désiré et réel)
- Rollback automatique en cas d'échec
- Interface web pour visualisation

## Structure

```
argocd/
├── applications/               # Application CRDs
│   ├── app-frontend.yaml       # Application Next.js
│   ├── app-backend.yaml        # Application NestJS
│   ├── app-postgresql.yaml     # Application PostgreSQL
│   ├── app-redis.yaml          # Application Redis
│   ├── app-monitoring.yaml     # Application monitoring stack
│   └── app-of-apps.yaml       # App-of-apps pattern (parent)
└── projects/
    ├── production.yaml         # AppProject production
    └── staging.yaml            # AppProject staging
```

## Stratégie de déploiement

- **Staging** : Auto-sync activé (déploiement automatique à chaque push)
- **Production** : Sync manuel requis (approval via PR ou UI ArgoCD)
- **Rollback** : Automatique si les health checks échouent

## Accès

```
URL : https://argocd.votre-domaine.com
User : admin
Password : (généré à l'installation, stocké dans sealed-secret)
```
