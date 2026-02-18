# CI/CD Pipeline

## Architecture

```
Developer                GitHub                    Docker Hub         K3s Cluster
    │                       │                          │                   │
    │  git push             │                          │                   │
    ├──────────────────────►│                          │                   │
    │                       │  GitHub Actions CI       │                   │
    │                       ├─────────────────┐        │                   │
    │                       │  1. Lint         │        │                   │
    │                       │  2. Test         │        │                   │
    │                       │  3. Security Scan│        │                   │
    │                       │  4. Build Docker │        │                   │
    │                       ├─────────────────┘        │                   │
    │                       │                          │                   │
    │                       │  docker push             │                   │
    │                       ├─────────────────────────►│                   │
    │                       │                          │                   │
    │                       │  Update K8s manifest     │                   │
    │                       │  (image tag)             │                   │
    │                       ├──────────┐               │                   │
    │                       │  git push│               │                   │
    │                       ├──────────┘               │                   │
    │                       │                          │     ArgoCD        │
    │                       │  Detect change ──────────┼──────────────────►│
    │                       │                          │  Sync manifests   │
    │                       │                          │  Pull image       │
    │                       │                          │◄─────────────────►│
    │                       │                          │                   │
    │  Notification Slack   │                          │                   │
    │◄──────────────────────┤                          │                   │
```

## Workflows

| Workflow | Trigger | Jobs | Description |
|----------|---------|------|-------------|
| ci-backend | push main/develop, PR | lint, test, scan, build, notify | CI/CD Backend NestJS |
| ci-frontend | push main/develop, PR | lint, test, build, scan, push, notify | CI/CD Frontend Next.js |
| ci-infrastructure | push k8s/, terraform/ | validate-k8s, validate-terraform | Validation IaC |
| deploy-staging | push develop | deploy via ArgoCD | Deploy staging |
| deploy-production | tag v* | validate, deploy (approval), smoke tests | Deploy production |
| security-scan | cron lundi 2h | Trivy, OWASP, Kubesec | Scan securite hebdo |

## Secrets GitHub requis

Configurer dans **Settings > Secrets and variables > Actions** :

| Secret | Description | Exemple |
|--------|-------------|---------|
| DOCKER_USERNAME | Username Docker Hub | your-username |
| DOCKER_PASSWORD | Password/Token Docker Hub | dckr_pat_xxx |
| SLACK_WEBHOOK_URL | Webhook Slack notifications | https://hooks.slack.com/... |
| ARGOCD_SERVER | URL serveur ArgoCD | argocd.saas.local |
| ARGOCD_AUTH_TOKEN | Token auth ArgoCD | eyJhbGci... |

## Environments GitHub

Configurer dans **Settings > Environments** :

### staging
- Pas de protection (deploy automatique sur develop)

### production
- **Required reviewers** : au moins 1 approbateur
- **Wait timer** : 0 minutes (optionnel)
- **Deployment branches** : tags v*

## Procedures

### Feature development
```
1. git checkout -b feature/ma-feature develop
2. Developper + tests locaux
3. git push origin feature/ma-feature
4. Creer Pull Request → CI lance lint + test + security
5. Code review + approve
6. Merge vers develop → deploy staging automatique
7. Tests staging OK
8. Merge vers main → CI build Docker + update manifest → ArgoCD sync
```

### Release production
```
1. Verifier que main est stable
2. git tag -a v1.2.3 -m "Release 1.2.3"
3. git push origin v1.2.3
4. Workflow deploy-production declenche
5. Approbation manuelle requise
6. Deploy via ArgoCD
7. Smoke tests automatiques
8. Rollback automatique si echec
```

### Hotfix
```
1. git checkout -b hotfix/fix-critical main
2. Fix + test
3. git push origin hotfix/fix-critical
4. PR vers main → CI
5. Merge → build → deploy
6. git tag -a v1.2.4 -m "Hotfix"
7. git push origin v1.2.4
8. Backport vers develop si necessaire
```

## Best Practices

- **Branch protection** sur main : require PR + 1 review
- **Semantic versioning** : v1.2.3 (major.minor.patch)
- **Immutable tags** : sha court (abc1234) + latest
- **Pas de deploy direct** : toujours via Git → CI/CD → ArgoCD
- **Secrets** : jamais dans le code, toujours GitHub Secrets ou SealedSecrets
- **Tests** : bloquants (lint + test doivent passer avant build)
- **Security** : scan a chaque PR + scan hebdomadaire
