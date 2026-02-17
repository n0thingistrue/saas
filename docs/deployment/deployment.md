# Guide de déploiement complet

## Prérequis

### Outils locaux

```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubeseal
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep tag_name | cut -d '"' -f4 | cut -c2-)
wget "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xvzf kubeseal-*.tar.gz kubeseal && sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# k6
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D68
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt update && sudo apt install k6
```

### Hetzner Cloud

1. Créer un compte sur [console.hetzner.cloud](https://console.hetzner.cloud)
2. Créer un projet "saas-production"
3. Générer un API Token (Read/Write) : API Tokens → Generate API Token
4. Uploader votre clé SSH publique : Security → SSH Keys

### DNS

Configurer les enregistrements DNS pointant vers la Floating IP :
- `votre-domaine.com` → A → `<floating-ip>`
- `*.votre-domaine.com` → A → `<floating-ip>`
- `api.votre-domaine.com` → A → `<floating-ip>`

## Phase 1 : Infrastructure (Terraform)

```bash
cd terraform

# Copier et éditer les variables
cp environments/prod/terraform.tfvars.example environments/prod/terraform.tfvars
# Éditer : hcloud_token, ssh_key_name, domain, email

# Initialiser Terraform
terraform init

# Vérifier le plan
terraform plan -var-file=environments/prod/terraform.tfvars

# Appliquer
terraform apply -var-file=environments/prod/terraform.tfvars

# Noter les outputs
terraform output
```

## Phase 2 : Préparation des nodes

```bash
# Depuis votre machine locale
cd scripts/install

# Installer les prérequis sur les 2 nodes
./00-prereqs.sh

# Installer K3s server sur Node 1
./01-install-k3s-server.sh

# Installer K3s agent sur Node 2
./02-install-k3s-agent.sh

# Vérifier
./03-post-install.sh
```

## Phase 3 : Bootstrap Kubernetes

```bash
# Bootstrap automatique complet
cd scripts/bootstrap
./bootstrap.sh --env production

# Ou étape par étape :
./01-namespaces.sh
./02-sealed-secrets.sh
./03-cert-manager.sh
./04-traefik.sh
./05-postgresql.sh
./06-redis.sh
./07-samba-ad.sh
./08-backend.sh
./09-frontend.sh
./10-monitoring.sh
./11-security.sh
./12-argocd.sh
```

## Phase 4 : Vérification

```bash
# Nodes
kubectl get nodes -o wide

# Tous les pods
kubectl get pods --all-namespaces

# Services
kubectl get svc --all-namespaces

# Ingress
kubectl get ingressroute -n production

# Certificats TLS
kubectl get certificates -n ingress

# PostgreSQL replication
kubectl exec -n production postgresql-0 -- patronictl list

# Redis Sentinel
kubectl exec -n production redis-0 -- redis-cli info replication
```

## Phase 5 : Tests

```bash
# Tests de charge
cd scripts/testing
./run-load-test.sh --scenario smoke

# Test failover PostgreSQL
cd scripts/disaster-recovery
./test-failover-pg.sh

# Test failover Redis
./test-failover-redis.sh

# Rapport compliance
cd scripts/compliance
./generate-report.sh
```

## Rollback

En cas de problème, ArgoCD permet un rollback instantané :
```bash
# Via CLI
argocd app rollback <app-name>

# Via kubectl
kubectl rollout undo deployment/<name> -n production
```
