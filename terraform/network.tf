# =============================================================================
# Réseau privé Hetzner Cloud
# =============================================================================
# Réseau isolé entre les 2 nodes pour le trafic interne :
#   - Communication K3s (control plane ↔ worker)
#   - Réplication PostgreSQL (primary ↔ standby)
#   - Réplication Redis (master ↔ replica)
#   - Métriques Prometheus
#
# Ce réseau est en plus du tunnel WireGuard qui ajoute une couche
# de chiffrement pour le trafic sensible.
# =============================================================================

# -----------------------------------------------------------------------------
# Réseau privé principal
# CIDR : 10.10.0.0/16 (65 534 adresses possibles)
# -----------------------------------------------------------------------------
resource "hcloud_network" "main" {
  name     = "${local.name_prefix}-network"
  ip_range = var.network_cidr

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# Sous-réseau principal
# CIDR : 10.10.0.0/24 (254 adresses, suffisant pour 2 nodes + services)
# Zone : eu-central (couvre fsn1, nbg1, hel1)
# -----------------------------------------------------------------------------
resource "hcloud_network_subnet" "main" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = var.subnet_cidr
}

# -----------------------------------------------------------------------------
# Attachement réseau - Node 1
# IP fixe : 10.10.0.2 (premier serveur du sous-réseau)
# -----------------------------------------------------------------------------
resource "hcloud_server_network" "node1" {
  server_id  = hcloud_server.node1.id
  network_id = hcloud_network.main.id
  ip         = var.node1_private_ip

  # Attendre que le sous-réseau soit créé
  depends_on = [hcloud_network_subnet.main]
}

# -----------------------------------------------------------------------------
# Attachement réseau - Node 2
# IP fixe : 10.10.0.3 (second serveur du sous-réseau)
# -----------------------------------------------------------------------------
resource "hcloud_server_network" "node2" {
  server_id  = hcloud_server.node2.id
  network_id = hcloud_network.main.id
  ip         = var.node2_private_ip

  depends_on = [hcloud_network_subnet.main]
}
