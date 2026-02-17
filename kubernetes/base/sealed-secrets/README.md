# Sealed Secrets - Gestion des secrets chiffres

## Pourquoi Sealed Secrets ?

Les Secrets Kubernetes sont encodes en base64, pas chiffres.
Commiter un Secret dans Git expose les donnees sensibles (mots de passe, tokens).

Sealed Secrets resout ce probleme :
- Les secrets sont **chiffres** avec une cle publique RSA 4096 bits
- Seul le controller dans le cluster peut les **dechiffrer**
- Les SealedSecrets peuvent etre **commites dans Git** en toute securite

## Architecture

```
Developer                    Cluster K8s
    |                            |
    |  1. kubeseal encrypt       |
    |  (cle publique) --------->  |
    |                            |
    |  2. git push               |
    |  (SealedSecret YAML)       |
    |                            |
    |                    3. Controller detecte
    |                       le SealedSecret
    |                            |
    |                    4. Dechiffre avec
    |                       la cle privee
    |                            |
    |                    5. Cree un Secret
    |                       K8s standard
```

## Installation

Le controller est deploye automatiquement par le bootstrap :
```bash
kubectl apply -f kubernetes/base/sealed-secrets/
```

Ou via Helm (methode recommandee, dans bootstrap.sh) :
```bash
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace security
```

## Utilisation

### 1. Recuperer la cle publique

```bash
# La cle publique est telechargeee automatiquement par kubeseal
# Optionnel : sauvegarder localement
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=security \
  > sealed-secrets-pub.pem
```

### 2. Creer un secret classique (ne pas commiter !)

```bash
# Creer un secret K8s standard (fichier temporaire)
kubectl create secret generic my-secret \
  --namespace production \
  --from-literal=password='mon-mot-de-passe' \
  --from-literal=api-key='ma-cle-api' \
  --dry-run=client -o yaml > /tmp/my-secret.yaml
```

### 3. Chiffrer avec kubeseal

```bash
# Chiffrer le secret
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=security \
  --format yaml \
  < /tmp/my-secret.yaml \
  > kubernetes/secrets/my-sealed-secret.yaml

# Supprimer le secret en clair
rm /tmp/my-secret.yaml
```

### 4. Appliquer le SealedSecret

```bash
kubectl apply -f kubernetes/secrets/my-sealed-secret.yaml

# Verifier que le Secret a ete cree
kubectl get secret my-secret -n production
```

### 5. Commiter dans Git

```bash
# Le SealedSecret est chiffre, safe to commit
git add kubernetes/secrets/my-sealed-secret.yaml
git commit -m "feat: add my-secret sealed secret"
```

## Secrets necessaires pour le projet

| Secret | Namespace | Contenu |
|--------|-----------|---------|
| `postgresql-credentials` | production | postgres password, replication password |
| `redis-credentials` | production | redis password |
| `samba-ad-credentials` | production | admin password, realm, domain |
| `backend-secrets` | production | JWT secret, session secret, DB URL |
| `frontend-secrets` | production | NEXTAUTH_SECRET, API URL |
| `s3-credentials` | backup | S3 access key, secret key, endpoint |
| `grafana-credentials` | monitoring | admin password |
| `argocd-credentials` | argocd | admin password, GitHub token |

### Exemple : creer le secret PostgreSQL

```bash
kubectl create secret generic postgresql-credentials \
  --namespace production \
  --from-literal=POSTGRES_PASSWORD='votre-mdp-fort' \
  --from-literal=POSTGRES_REPLICATION_PASSWORD='mdp-replication' \
  --from-literal=POSTGRES_USER='postgres' \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=security \
  --format yaml \
  > kubernetes/secrets/postgresql-sealed-secret.yaml
```

## Backup de la cle de chiffrement

**CRITIQUE** : Si la cle privee est perdue, TOUS les SealedSecrets
deviennent inutilisables. Sauvegardez la cle :

```bash
# Backup de la cle (a stocker en lieu sur, PAS dans Git)
kubectl get secret -n security \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > /safe/location/sealed-secrets-key-backup.yaml
```

## Rotation des cles

Le controller genere de nouvelles cles automatiquement (par defaut tous les 30 jours).
Les anciennes cles sont conservees pour dechiffrer les anciens SealedSecrets.

Pour forcer une rotation :
```bash
# Supprimer la cle actuelle (le controller en regenere une)
kubectl delete secret -n security \
  -l sealedsecrets.bitnami.com/sealed-secrets-key

# Rechiffrer tous les SealedSecrets avec la nouvelle cle
# (optionnel mais recommande)
for f in kubernetes/secrets/*.yaml; do
  kubeseal --re-encrypt < "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
```

## Troubleshooting

### Le SealedSecret n'est pas dechiffre

```bash
# Verifier le controller
kubectl get pods -n security -l app=sealed-secrets
kubectl logs -n security -l app=sealed-secrets

# Verifier le status du SealedSecret
kubectl get sealedsecret -n production <name> -o yaml | grep -A5 status
```

### Erreur "no key could decrypt secret"

La cle a change (reinstallation cluster). Solutions :
1. Restaurer la cle depuis le backup
2. Rechiffrer les secrets avec la nouvelle cle publique
