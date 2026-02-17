# =============================================================================
# Serveurs Cloud - Hetzner
# =============================================================================
# 2 serveurs dédiés (vCPU dédiées, pas partagées) pour garantir
# des performances constantes requises par PostgreSQL et K3s.
#
# Node 1 (CCX33) : 16 vCPU, 32GB RAM, 320GB NVMe
#   → Control plane K3s + workloads principaux + monitoring
#
# Node 2 (CCX23) : 4 vCPU, 16GB RAM, 160GB NVMe
#   → Worker K3s + replicas HA + sécurité + staging
# =============================================================================

# -----------------------------------------------------------------------------
# Node 1 - Serveur principal (Control Plane + Production Core)
# -----------------------------------------------------------------------------
resource "hcloud_server" "node1" {
  name        = "${local.name_prefix}-node1"
  image       = var.server_image
  server_type = var.node1_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.default.id]

  # Cloud-init pour configuration initiale automatique
  user_data = local.cloud_init_base

  labels = merge(local.common_labels, {
    role = "control-plane"
    node = "node1"
  })

  # Protection contre suppression accidentelle en production
  delete_protection  = var.environment == "prod" ? true : false
  rebuild_protection = var.environment == "prod" ? true : false

  # Le réseau public est nécessaire pour l'accès SSH et le trafic entrant
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    # Empêcher la destruction accidentelle du serveur (données)
    # Commenter cette ligne pour permettre terraform destroy
    # prevent_destroy = true

    # Ne pas recréer le serveur si le cloud-init change
    ignore_changes = [user_data, ssh_keys]
  }
}

# -----------------------------------------------------------------------------
# Node 2 - Serveur secondaire (Worker + HA + Security)
# -----------------------------------------------------------------------------
resource "hcloud_server" "node2" {
  name        = "${local.name_prefix}-node2"
  image       = var.server_image
  server_type = var.node2_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.default.id]

  user_data = local.cloud_init_base

  labels = merge(local.common_labels, {
    role = "worker"
    node = "node2"
  })

  delete_protection  = var.environment == "prod" ? true : false
  rebuild_protection = var.environment == "prod" ? true : false

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    ignore_changes = [user_data, ssh_keys]
  }
}

# -----------------------------------------------------------------------------
# Reverse DNS - Associer le domaine aux IPs publiques
# Utile pour la délivrabilité email et la vérification TLS
# -----------------------------------------------------------------------------
resource "hcloud_rdns" "node1_ipv4" {
  server_id  = hcloud_server.node1.id
  ip_address = hcloud_server.node1.ipv4_address
  dns_ptr    = "node1.${var.domain}"
}

resource "hcloud_rdns" "node2_ipv4" {
  server_id  = hcloud_server.node2.id
  ip_address = hcloud_server.node2.ipv4_address
  dns_ptr    = "node2.${var.domain}"
}
