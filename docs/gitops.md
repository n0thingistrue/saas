# GitOps - Principes et Implementation

## Principes GitOps

```
                    ┌──────────────────────┐
                    │     Git Repository    │
                    │  (Single Source of    │
                    │       Truth)          │
                    └──────────┬───────────┘
                               │
                     Desired State (declaratif)
                               │
                               ▼
                    ┌──────────────────────┐
                    │    ArgoCD Controller  │
                    │  (Reconciliation     │
                    │       Loop)           │
                    └──────────┬───────────┘
                               │
                    Compare desired vs live
                               │
                               ▼
                    ┌──────────────────────┐
                    │   Kubernetes Cluster  │
                    │    (Live State)       │
                    └──────────────────────┘
```

## 4 Principes fondamentaux

### 1. Declaratif
Toute l'infrastructure est decrite sous forme de manifests declaratifs (YAML).
Le systeme converge vers l'etat desire automatiquement.

### 2. Versionne dans Git
Git est la seule source de verite. Tout changement passe par un commit Git.
L'historique complet est dans `git log`.

### 3. Automatiquement applique
ArgoCD detecte les changements dans Git et applique automatiquement
les modifications au cluster (reconciliation loop).

### 4. Self-healing
Si l'etat du cluster diverge de Git (modification manuelle, crash),
ArgoCD re-applique automatiquement l'etat desire.

## Avantages

| Avantage | Description |
|----------|-------------|
| Audit trail | Chaque changement est un commit Git avec auteur, date, message |
| Rollback facile | `git revert` ou `argocd app rollback` |
| Reproductibilite | Meme code = meme infrastructure |
| Collaboration | Pull Request = code review sur l'infra |
| Disaster recovery | Reconstruire le cluster depuis Git |
| Separation of concerns | CI (build) vs CD (deploy) decouples |

## Workflow complet

```
1. Developer modifie un fichier K8s
   └── Ex: augmenter replicas backend de 3 a 4

2. Git commit + push
   └── git commit -m "scale: increase backend to 4 replicas"
   └── git push origin main

3. GitHub Actions CI
   └── Valide YAML, kustomize build, Checkov scan
   └── Si echec → PR bloquee, notification Slack

4. ArgoCD detecte le changement (poll 3 min)
   └── Compare Git (desired) vs Cluster (live)
   └── Detecte diff: replicas 3 → 4

5. ArgoCD synchronise (si automated)
   └── kubectl apply le manifest modifie
   └── Kubernetes scale le deployment

6. ArgoCD verifie la sante (health check)
   └── Attend que tous les pods soient Ready
   └── Status: Healthy + Synced

7. Notification
   └── ArgoCD → Slack: "backend deployed successfully"
```

## Pattern App of Apps

```
app-of-apps (Application parent)
├── app-databases.yaml     (Wave 0)
├── app-samba-ad.yaml      (Wave 1, manual)
├── app-backend.yaml       (Wave 2)
├── app-frontend.yaml      (Wave 3)
├── app-monitoring.yaml    (Wave 4)
└── app-ingress.yaml       (Wave 5)
```

L'App of Apps est une Application ArgoCD qui pointe vers le dossier
contenant toutes les autres Applications. Deployer l'App of Apps
deploie automatiquement toute l'infrastructure dans l'ordre des sync-waves.

## Gestion des Secrets

```
Secret → SealedSecret (chiffre) → Git → ArgoCD → Kubernetes Secret

1. Creer le Secret en clair
   kubectl create secret generic my-secret --from-literal=KEY=value --dry-run=client -o yaml

2. Chiffrer avec kubeseal
   kubeseal --format yaml > my-sealed-secret.yaml

3. Committer le SealedSecret (chiffre) dans Git
   git add my-sealed-secret.yaml && git commit -m "add sealed secret"

4. ArgoCD deploie le SealedSecret
   sealed-secrets-controller le dechiffre en Secret Kubernetes
```

## Multi-environnements

```
kubernetes/
├── base/           # Ressources communes
├── overlays/
│   ├── staging/    # Kustomize overlay staging
│   │   └── kustomization.yaml  (replicas: 1, resources reduced)
│   └── production/ # Kustomize overlay production
│       └── kustomization.yaml  (replicas: 3, resources full)
```

ArgoCD Applications pointent vers l'overlay correspondant :
- `app-backend-staging` → `kubernetes/overlays/staging/backend`
- `app-backend` → `kubernetes/overlays/production/backend`

## Troubleshooting GitOps

| Probleme | Cause | Solution |
|----------|-------|----------|
| App OutOfSync | Manifest Git != cluster | `argocd app sync <app>` |
| App Degraded | Pod not ready | Check pod logs, events |
| Sync Failed | RBAC, invalid manifest | `argocd app get <app>` → Events |
| Drift detected | Modification manuelle | Self-heal corrige automatiquement |
| Secret change | SealedSecret not applied | Verifier sealed-secrets-controller |
| Image not found | Registry auth failed | Verifier imagePullSecrets |
| Stuck Progressing | Deployment timeout | Check resources, PDB, node capacity |
