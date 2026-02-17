# =============================================================================
# Load Balancer - Hetzner Cloud
# =============================================================================
# Load Balancer Hetzner pour distribuer le trafic HTTPS entre les nodes.
#
# Le LB Hetzner fournit :
#   - Health checks automatiques sur les targets
#   - Répartition du trafic (round-robin ou least-connections)
#   - Retrait automatique d'un node défaillant
#   - Proxy Protocol pour transmettre l'IP client réelle à Traefik
#
# Flow du trafic :
#   Client → Floating IP → Load Balancer → Traefik (Node 1 ou Node 2)
#
# Note : Le LB11 Hetzner supporte jusqu'à 25 targets et 10k connexions
# simultanées, largement suffisant pour cette infrastructure.
# =============================================================================

# -----------------------------------------------------------------------------
# Load Balancer
# Type LB11 : le plus petit, suffisant pour 2 targets (~5€/mois)
# Situé dans le même datacenter que les serveurs pour la latence minimale
# -----------------------------------------------------------------------------
resource "hcloud_load_balancer" "main" {
  name               = "${local.name_prefix}-lb"
  load_balancer_type = var.lb_type
  location           = var.location

  labels = local.common_labels

  # Algorithme de répartition
  # least_connections : envoie au serveur ayant le moins de connexions actives
  # Meilleur que round_robin quand les serveurs ont des capacités différentes
  algorithm {
    type = "least_connections"
  }
}

# -----------------------------------------------------------------------------
# Attachement au réseau privé
# Le LB communique avec les nodes via le réseau privé (pas d'exposition publique
# du trafic inter-LB/serveurs)
# -----------------------------------------------------------------------------
resource "hcloud_load_balancer_network" "main" {
  load_balancer_id = hcloud_load_balancer.main.id
  network_id       = hcloud_network.main.id

  depends_on = [hcloud_network_subnet.main]
}

# -----------------------------------------------------------------------------
# Target Node 1
# Utilise le réseau privé pour la communication LB → serveur
# -----------------------------------------------------------------------------
resource "hcloud_load_balancer_target" "node1" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.main.id
  server_id        = hcloud_server.node1.id
  use_private_ip   = true

  depends_on = [
    hcloud_load_balancer_network.main,
    hcloud_server_network.node1
  ]
}

# -----------------------------------------------------------------------------
# Target Node 2
# -----------------------------------------------------------------------------
resource "hcloud_load_balancer_target" "node2" {
  type             = "server"
  load_balancer_id = hcloud_load_balancer.main.id
  server_id        = hcloud_server.node2.id
  use_private_ip   = true

  depends_on = [
    hcloud_load_balancer_network.main,
    hcloud_server_network.node2
  ]
}

# -----------------------------------------------------------------------------
# Service HTTPS (port 443)
# Passthrough TCP : le TLS est terminé par Traefik (pas le LB)
# Cela permet à Traefik de gérer les certificats Let's Encrypt
# et d'appliquer les rules WAF ModSecurity sur le trafic déchiffré
# -----------------------------------------------------------------------------
resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.main.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 10
    timeout  = 5
    retries  = 3
  }

  # Proxy Protocol v2 pour transmettre l'IP client réelle à Traefik
  proxyprotocol = true
}

# -----------------------------------------------------------------------------
# Service HTTP (port 80)
# Également en passthrough TCP pour que Traefik gère la redirection HTTP→HTTPS
# -----------------------------------------------------------------------------
resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.main.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80

  health_check {
    protocol = "tcp"
    port     = 80
    interval = 15
    timeout  = 5
    retries  = 3
  }

  proxyprotocol = true
}
