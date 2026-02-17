# =============================================================================
# Floating IP - Hetzner Cloud
# =============================================================================
# La Floating IP est l'adresse IP publique stable qui sert de point d'entrée
# pour tout le trafic vers l'infrastructure.
#
# Avantages :
#   - IP indépendante des serveurs (survit aux rebuilds)
#   - Basculable entre Node 1 et Node 2 pour le failover
#   - Point d'entrée DNS unique (A record → Floating IP)
#
# En fonctionnement normal, assignée au Node 1 (Traefik).
# En cas de failover Node 1, basculable vers Node 2 via API Hetzner.
# =============================================================================

# -----------------------------------------------------------------------------
# Floating IP
# Assignée par défaut au Node 1 (serveur principal / Traefik)
# Type : IPv4 (les navigateurs gèrent mieux IPv4 pour le moment)
# -----------------------------------------------------------------------------
resource "hcloud_floating_ip" "main" {
  name          = "${local.name_prefix}-floating-ip"
  type          = "ipv4"
  home_location = var.location
  description   = "IP publique principale - point d'entree DNS"

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# Assignation de la Floating IP au Node 1
# En cas de failover, cette assignation sera modifiée via l'API Hetzner
# par le script de disaster recovery.
# -----------------------------------------------------------------------------
resource "hcloud_floating_ip_assignment" "main" {
  floating_ip_id = hcloud_floating_ip.main.id
  server_id      = hcloud_server.node1.id
}

# -----------------------------------------------------------------------------
# Reverse DNS pour la Floating IP
# Le PTR record est important pour la validation TLS et la réputation IP
# -----------------------------------------------------------------------------
resource "hcloud_rdns" "floating_ip" {
  floating_ip_id = hcloud_floating_ip.main.id
  ip_address     = hcloud_floating_ip.main.ip_address
  dns_ptr        = var.domain
}
