# ArgoCD - GitOps Controller

## Architecture

```
GitHub Repository                    ArgoCD (K3s)
     │                                    │
     │  git push                          │  Poll every 3min
     ├───────────────────────────────────►│
     │                                    │  Detect diff
     │                                    │
     │                              ┌─────┴─────┐
     │                              │ App of Apps│
     │                              └─────┬─────┘
     │                                    │
     │                    ┌───────────────┼───────────────┐
     │                    │               │               │
     │              ┌─────┴────┐   ┌──────┴─────┐  ┌─────┴────┐
     │              │Databases │   │Applications│  │Monitoring│
     │              │ Wave 0   │   │ Wave 2-3   │  │ Wave 4   │
     │              └──────────┘   └────────────┘  └──────────┘
     │              ┌──────────┐   ┌────────────┐
     │              │Samba-AD  │   │  Ingress   │
     │              │ Wave 1   │   │  Wave 5    │
     │              │ MANUAL   │   └────────────┘
     │              └──────────┘
```

## Installation

```bash
# 1. Creer le namespace
kubectl create namespace argocd

# 2. Installer ArgoCD (manifest officiel)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. Attendre que tous les pods soient ready
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# 4. Recuperer le mot de passe initial admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# 5. Appliquer la configuration personnalisee
kubectl apply -f kubernetes/argocd/argocd-configmap.yaml
kubectl apply -f kubernetes/argocd/argocd-rbac-configmap.yaml
kubectl apply -f kubernetes/argocd/argocd-notifications-configmap.yaml

# 6. Deployer l'IngressRoute
kubectl apply -f kubernetes/argocd/argocd-ingress.yaml

# 7. Installer le CLI ArgoCD
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# 8. Se connecter
argocd login argocd.saas.local --grpc-web

# 9. Changer le mot de passe admin
argocd account update-password

# 10. Ajouter le repository Git
argocd repo add https://github.com/your-username/infrastructure-rncp.git

# 11. Deployer l'App of Apps
kubectl apply -f kubernetes/argocd/applications/app-of-apps.yaml
```

## Applications

| Application | Path | Namespace | Sync Policy | Wave |
|------------|------|-----------|-------------|------|
| databases | kubernetes/databases | production | Automated | 0 |
| samba-ad | kubernetes/apps/samba-ad | production | **Manual** | 1 |
| backend | kubernetes/apps/backend | production | Automated | 2 |
| frontend | kubernetes/apps/frontend | production | Automated | 3 |
| monitoring | kubernetes/monitoring | monitoring | Automated | 4 |
| ingress | kubernetes/ingress | ingress | Automated | 5 |

## Workflow GitOps

```
1. Modifier un fichier Kubernetes localement
2. git add . && git commit -m "update backend resources"
3. git push origin main
4. ArgoCD detecte le changement (poll 3min ou webhook)
5. ArgoCD compare le desired state (Git) vs live state (cluster)
6. ArgoCD synchronise automatiquement (si automated)
7. Verification dans l'UI ArgoCD
```

## Rollback

```bash
# Via ArgoCD CLI
argocd app rollback backend

# Via Git (revert le commit)
git revert HEAD && git push origin main

# Voir l'historique des deployments
argocd app history backend
```

## Commandes utiles

```bash
# Lister toutes les applications
argocd app list

# Voir le statut d'une application
argocd app get backend

# Sync force
argocd app sync backend

# Sync toutes les apps
for app in $(argocd app list -o name); do argocd app sync $app; done

# Voir les differences (diff)
argocd app diff backend

# Supprimer une application
argocd app delete backend

# Voir les logs ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## Troubleshooting

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| App OutOfSync | `argocd app diff <app>` | Verifier les changements, sync |
| Sync failed | `argocd app get <app>` → Events | Check RBAC, repo access |
| Health Degraded | `argocd app get <app>` → Resources | Check pod status, logs |
| Repo inaccessible | `argocd repo list` | Check credentials, URL |
| Permission denied | Check argocd-rbac-cm | Ajouter permissions au role |
| CRDs missing | `kubectl get crd` | Installer les CRDs manuellement d'abord |
