# Terraform - Infrastructure Hetzner Cloud

## Vue d'ensemble

Provisionnement de l'infrastructure complète sur Hetzner Cloud :
- 2 serveurs cloud (CCX33 + CCX23)
- Réseau privé isolé (VLAN)
- Floating IP pour haute disponibilité
- Load Balancer Hetzner
- Volumes persistants pour données
- Object Storage S3 pour backups
- Règles firewall par service

## Structure

```
terraform/
├── main.tf                    # Configuration principale + backend
├── providers.tf               # Provider Hetzner + versions
├── variables.tf               # Variables globales
├── outputs.tf                 # Outputs (IPs, IDs, etc.)
├── network.tf                 # Réseau privé + sous-réseaux
├── servers.tf                 # Serveurs cloud (Node 1 + Node 2)
├── firewall.tf                # Règles firewall Hetzner
├── volumes.tf                 # Volumes persistants
├── floating-ip.tf             # Floating IP + assignation
├── load-balancer.tf           # Load Balancer Hetzner
├── s3.tf                      # Object Storage S3 (backups)
├── ssh-keys.tf                # Clés SSH
├── environments/
│   ├── prod/
│   │   ├── terraform.tfvars.example
│   │   └── backend.hcl
│   └── staging/
│       ├── terraform.tfvars.example
│       └── backend.hcl
└── modules/                   # Modules réutilisables
    ├── server/
    ├── network/
    ├── firewall/
    ├── volume/
    └── s3/
```

## Prérequis

- Terraform >= 1.7
- Compte Hetzner Cloud
- API Token Hetzner (Read/Write)
- Clé SSH uploadée dans Hetzner Console

## Utilisation

```bash
# Initialiser
cd terraform
terraform init

# Planifier (production)
terraform plan -var-file=environments/prod/terraform.tfvars

# Appliquer
terraform apply -var-file=environments/prod/terraform.tfvars

# Détruire (attention !)
terraform destroy -var-file=environments/prod/terraform.tfvars
```

## Variables importantes

| Variable | Description | Défaut |
|----------|-------------|--------|
| `hcloud_token` | API Token Hetzner | - |
| `environment` | Environnement (prod/staging) | prod |
| `location` | Datacenter Hetzner | fsn1 |
| `node1_type` | Type serveur Node 1 | ccx33 |
| `node2_type` | Type serveur Node 2 | ccx23 |
| `ssh_key_name` | Nom clé SSH Hetzner | - |

## Outputs

Après `terraform apply`, les outputs suivants sont disponibles :

- `node1_ip` / `node2_ip` : IPs publiques des serveurs
- `node1_private_ip` / `node2_private_ip` : IPs réseau privé
- `floating_ip` : IP flottante (entrée DNS)
- `lb_ip` : IP du Load Balancer
- `s3_endpoint` : Endpoint Object Storage
- `network_id` : ID du réseau privé
