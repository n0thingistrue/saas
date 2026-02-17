# =============================================================================
# Variables globales - Infrastructure SaaS Hetzner Cloud
# =============================================================================
# Toutes les variables configurables sont centralisées ici.
# Les valeurs par défaut sont pour la production.
# Surcharger via terraform.tfvars par environnement.
# =============================================================================

# -----------------------------------------------------------------------------
# Authentification Hetzner
# -----------------------------------------------------------------------------

variable "hcloud_token" {
  description = "Token API Hetzner Cloud (Read/Write). Ne jamais commiter en clair."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Environnement
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Nom de l'environnement (prod, staging)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "L'environnement doit être 'prod' ou 'staging'."
  }
}

variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe pour les ressources"
  type        = string
  default     = "saas"
}

# -----------------------------------------------------------------------------
# Localisation
# -----------------------------------------------------------------------------

variable "location" {
  description = "Datacenter Hetzner (fsn1=Falkenstein, nbg1=Nuremberg, hel1=Helsinki)"
  type        = string
  default     = "fsn1"
}

# -----------------------------------------------------------------------------
# Serveurs
# -----------------------------------------------------------------------------

variable "node1_type" {
  description = "Type de serveur Node 1 (16 vCPU, 32GB RAM, 320GB). Dédié AMD."
  type        = string
  default     = "ccx33"
}

variable "node2_type" {
  description = "Type de serveur Node 2 (4 vCPU, 16GB RAM, 160GB). Dédié AMD."
  type        = string
  default     = "ccx23"
}

variable "server_image" {
  description = "Image OS pour les serveurs. Debian 12 recommandé pour K3s."
  type        = string
  default     = "debian-12"
}

# -----------------------------------------------------------------------------
# SSH
# -----------------------------------------------------------------------------

variable "ssh_key_name" {
  description = "Nom de la clé SSH enregistrée dans Hetzner Console"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Chemin vers la clé SSH publique locale (pour upload si nécessaire)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# -----------------------------------------------------------------------------
# Réseau
# -----------------------------------------------------------------------------

variable "network_cidr" {
  description = "CIDR du réseau privé Hetzner (cloud network)"
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR du sous-réseau principal"
  type        = string
  default     = "10.10.0.0/24"
}

variable "node1_private_ip" {
  description = "IP privée fixe du Node 1 dans le réseau Hetzner"
  type        = string
  default     = "10.10.0.2"
}

variable "node2_private_ip" {
  description = "IP privée fixe du Node 2 dans le réseau Hetzner"
  type        = string
  default     = "10.10.0.3"
}

# -----------------------------------------------------------------------------
# WireGuard VPN (overlay inter-nodes)
# -----------------------------------------------------------------------------

variable "wireguard_cidr" {
  description = "CIDR du réseau WireGuard entre les nodes"
  type        = string
  default     = "10.0.0.0/24"
}

variable "wireguard_port" {
  description = "Port UDP WireGuard"
  type        = number
  default     = 51820
}

# -----------------------------------------------------------------------------
# Volumes
# -----------------------------------------------------------------------------

variable "volume_postgresql_size" {
  description = "Taille du volume PostgreSQL en GB"
  type        = number
  default     = 50
}

variable "volume_postgresql_standby_size" {
  description = "Taille du volume PostgreSQL standby en GB"
  type        = number
  default     = 50
}

variable "volume_redis_size" {
  description = "Taille du volume Redis en GB"
  type        = number
  default     = 10
}

variable "volume_samba_size" {
  description = "Taille du volume Samba-AD en GB"
  type        = number
  default     = 20
}

variable "volume_monitoring_size" {
  description = "Taille du volume monitoring (Prometheus + Grafana + Loki) en GB"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------

variable "lb_type" {
  description = "Type de Load Balancer Hetzner"
  type        = string
  default     = "lb11"
}

# -----------------------------------------------------------------------------
# DNS / Domaine
# -----------------------------------------------------------------------------

variable "domain" {
  description = "Nom de domaine principal pour les services"
  type        = string
  default     = "example.com"
}

variable "email" {
  description = "Email pour Let's Encrypt et notifications"
  type        = string
  default     = "admin@example.com"
}

# -----------------------------------------------------------------------------
# S3 Object Storage (backups)
# -----------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "Nom du bucket S3 Hetzner pour les backups"
  type        = string
  default     = "saas-backups"
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "labels" {
  description = "Labels communs appliqués à toutes les ressources"
  type        = map(string)
  default = {
    project     = "saas"
    managed_by  = "terraform"
    environment = "prod"
  }
}
