# =============================================================================
# Firewall Hetzner Cloud
# =============================================================================
# Règles firewall au niveau Hetzner (avant même d'atteindre l'OS).
# Principe du moindre privilège : tout est bloqué sauf ce qui est explicitement
# autorisé. Séparation par rôle (control-plane vs worker).
#
# Couches de sécurité réseau :
#   1. Firewall Hetzner (ce fichier) - filtrage L3/L4
#   2. UFW sur les nodes - filtrage OS
#   3. NetworkPolicies K8s - filtrage pods
#   4. WireGuard - chiffrement inter-nodes
# =============================================================================

# -----------------------------------------------------------------------------
# Firewall Node 1 (Control Plane + Production)
# Ports ouverts :
#   - 22/TCP   : SSH (administration)
#   - 80/TCP   : HTTP (redirect vers HTTPS via Traefik)
#   - 443/TCP  : HTTPS (trafic applicatif)
#   - 6443/TCP : K3s API server (depuis Node 2 uniquement)
#   - 51820/UDP: WireGuard VPN (depuis Node 2 uniquement)
# -----------------------------------------------------------------------------
resource "hcloud_firewall" "node1" {
  name = "${local.name_prefix}-fw-node1"

  labels = merge(local.common_labels, {
    role = "control-plane"
  })

  # --- INGRESS ---

  # SSH - Accès administration
  # En production, restreindre à votre IP fixe
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "SSH administration"
  }

  # HTTP - Redirection vers HTTPS (Traefik)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "HTTP (redirect to HTTPS)"
  }

  # HTTPS - Trafic applicatif (Traefik)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "HTTPS application traffic"
  }

  # K3s API Server - Uniquement depuis Node 2 (réseau privé)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = ["${var.node2_private_ip}/32"]
    description = "K3s API server (Node 2 only)"
  }

  # WireGuard VPN - Uniquement depuis Node 2
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = tostring(var.wireguard_port)
    source_ips = ["0.0.0.0/0"]
    description = "WireGuard VPN"
  }

  # K3s inter-node communication (flannel VXLAN)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = ["${var.node2_private_ip}/32"]
    description = "K3s Flannel VXLAN (Node 2 only)"
  }

  # Kubelet metrics
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = ["${var.node2_private_ip}/32"]
    description = "Kubelet API (Node 2 only)"
  }

  # --- EGRESS ---
  # Tout le trafic sortant est autorisé (mises à jour, S3, registry, etc.)
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All outbound TCP"
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All outbound UDP"
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All outbound ICMP"
  }
}

# -----------------------------------------------------------------------------
# Firewall Node 2 (Worker + HA)
# Plus restrictif : pas de trafic HTTP/HTTPS direct (passe par le LB → Node 1)
# Ports ouverts :
#   - 22/TCP    : SSH
#   - 51820/UDP : WireGuard
#   - 8472/UDP  : Flannel VXLAN (depuis Node 1)
#   - 10250/TCP : Kubelet (depuis Node 1)
# -----------------------------------------------------------------------------
resource "hcloud_firewall" "node2" {
  name = "${local.name_prefix}-fw-node2"

  labels = merge(local.common_labels, {
    role = "worker"
  })

  # --- INGRESS ---

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "SSH administration"
  }

  # WireGuard VPN - Depuis Node 1
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = tostring(var.wireguard_port)
    source_ips = ["0.0.0.0/0"]
    description = "WireGuard VPN"
  }

  # K3s Flannel VXLAN - Depuis Node 1
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = ["${var.node1_private_ip}/32"]
    description = "K3s Flannel VXLAN (Node 1 only)"
  }

  # Kubelet API - Depuis Node 1 (control plane)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = ["${var.node1_private_ip}/32"]
    description = "Kubelet API (Node 1 only)"
  }

  # HTTP/HTTPS via Load Balancer (pour les replicas frontend/backend)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "HTTP via LB"
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
    description = "HTTPS via LB"
  }

  # --- EGRESS ---
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All outbound TCP"
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All outbound UDP"
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "All outbound ICMP"
  }
}

# -----------------------------------------------------------------------------
# Attachement des firewalls aux serveurs
# -----------------------------------------------------------------------------
resource "hcloud_firewall_attachment" "node1" {
  firewall_id = hcloud_firewall.node1.id
  server_ids  = [hcloud_server.node1.id]
}

resource "hcloud_firewall_attachment" "node2" {
  firewall_id = hcloud_firewall.node2.id
  server_ids  = [hcloud_server.node2.id]
}
