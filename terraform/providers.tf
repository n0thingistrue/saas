# =============================================================================
# Providers Configuration
# =============================================================================
# Provider Hetzner Cloud pour le provisionnement de l'infrastructure.
# Version minimale requise : Terraform 1.7+, hcloud provider 1.45+
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# -----------------------------------------------------------------------------
# Provider Hetzner Cloud
# Le token est passé via variable (jamais en dur dans le code)
# -----------------------------------------------------------------------------
provider "hcloud" {
  token = var.hcloud_token
}
