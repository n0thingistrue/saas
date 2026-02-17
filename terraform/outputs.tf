# =============================================================================
# Outputs - Valeurs exportées après terraform apply
# =============================================================================
# Ces outputs sont utilisés par :
#   - Les scripts d'installation K3s (IPs des nodes)
#   - Les manifests Kubernetes (configuration réseau)
#   - Les scripts de backup (endpoint S3)
#   - La documentation (accès, URLs)
# =============================================================================

# -----------------------------------------------------------------------------
# IPs publiques des serveurs
# -----------------------------------------------------------------------------

output "node1_ip" {
  description = "IP publique IPv4 du Node 1 (control plane)"
  value       = hcloud_server.node1.ipv4_address
}

output "node2_ip" {
  description = "IP publique IPv4 du Node 2 (worker)"
  value       = hcloud_server.node2.ipv4_address
}

output "node1_ipv6" {
  description = "IP publique IPv6 du Node 1"
  value       = hcloud_server.node1.ipv6_address
}

output "node2_ipv6" {
  description = "IP publique IPv6 du Node 2"
  value       = hcloud_server.node2.ipv6_address
}

# -----------------------------------------------------------------------------
# IPs privées (réseau interne Hetzner)
# -----------------------------------------------------------------------------

output "node1_private_ip" {
  description = "IP privée du Node 1 dans le réseau Hetzner"
  value       = var.node1_private_ip
}

output "node2_private_ip" {
  description = "IP privée du Node 2 dans le réseau Hetzner"
  value       = var.node2_private_ip
}

# -----------------------------------------------------------------------------
# Floating IP
# -----------------------------------------------------------------------------

output "floating_ip" {
  description = "Floating IP publique (point d'entrée DNS)"
  value       = hcloud_floating_ip.main.ip_address
}

output "floating_ip_id" {
  description = "ID de la Floating IP (pour scripts failover)"
  value       = hcloud_floating_ip.main.id
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------

output "lb_ip" {
  description = "IP publique du Load Balancer Hetzner"
  value       = hcloud_load_balancer.main.ipv4
}

output "lb_id" {
  description = "ID du Load Balancer"
  value       = hcloud_load_balancer.main.id
}

# -----------------------------------------------------------------------------
# Réseau
# -----------------------------------------------------------------------------

output "network_id" {
  description = "ID du réseau privé Hetzner"
  value       = hcloud_network.main.id
}

output "network_cidr" {
  description = "CIDR du réseau privé"
  value       = var.network_cidr
}

output "subnet_cidr" {
  description = "CIDR du sous-réseau"
  value       = var.subnet_cidr
}

# -----------------------------------------------------------------------------
# Volumes
# -----------------------------------------------------------------------------

output "volume_pg_primary_id" {
  description = "ID du volume PostgreSQL primary"
  value       = hcloud_volume.postgresql_primary.id
}

output "volume_pg_primary_path" {
  description = "Chemin de montage du volume PostgreSQL primary sur Node 1"
  value       = hcloud_volume.postgresql_primary.linux_device
}

output "volume_pg_standby_id" {
  description = "ID du volume PostgreSQL standby"
  value       = hcloud_volume.postgresql_standby.id
}

output "volume_pg_standby_path" {
  description = "Chemin de montage du volume PostgreSQL standby sur Node 2"
  value       = hcloud_volume.postgresql_standby.linux_device
}

output "volume_redis_path" {
  description = "Chemin de montage du volume Redis"
  value       = hcloud_volume.redis.linux_device
}

output "volume_samba_path" {
  description = "Chemin de montage du volume Samba-AD"
  value       = hcloud_volume.samba.linux_device
}

output "volume_monitoring_path" {
  description = "Chemin de montage du volume monitoring"
  value       = hcloud_volume.monitoring.linux_device
}

# -----------------------------------------------------------------------------
# Serveurs (IDs pour scripts API)
# -----------------------------------------------------------------------------

output "node1_id" {
  description = "ID Hetzner du Node 1 (pour API/scripts)"
  value       = hcloud_server.node1.id
}

output "node2_id" {
  description = "ID Hetzner du Node 2 (pour API/scripts)"
  value       = hcloud_server.node2.id
}

# -----------------------------------------------------------------------------
# Firewall IDs
# -----------------------------------------------------------------------------

output "firewall_node1_id" {
  description = "ID du firewall Node 1"
  value       = hcloud_firewall.node1.id
}

output "firewall_node2_id" {
  description = "ID du firewall Node 2"
  value       = hcloud_firewall.node2.id
}

# -----------------------------------------------------------------------------
# S3 Object Storage
# -----------------------------------------------------------------------------

output "s3_bucket" {
  description = "Nom du bucket S3 pour les backups"
  value       = var.s3_bucket_name
}

output "s3_endpoint" {
  description = "Endpoint S3 Hetzner"
  value       = "https://fsn1.your-objectstorage.com"
}

# -----------------------------------------------------------------------------
# Résumé de connexion (pour référence rapide)
# -----------------------------------------------------------------------------

output "connection_summary" {
  description = "Résumé des informations de connexion"
  value = <<-EOT

    ============================================
    Infrastructure SaaS - Résumé de connexion
    ============================================

    Node 1 (Control Plane):
      SSH: ssh root@${hcloud_server.node1.ipv4_address}
      Private IP: ${var.node1_private_ip}

    Node 2 (Worker):
      SSH: ssh root@${hcloud_server.node2.ipv4_address}
      Private IP: ${var.node2_private_ip}

    Floating IP: ${hcloud_floating_ip.main.ip_address}
    Load Balancer: ${hcloud_load_balancer.main.ipv4}

    DNS: Configurer ${var.domain} → ${hcloud_floating_ip.main.ip_address}

    Prochaine étape:
      cd scripts/install && ./01-install-k3s-server.sh

    ============================================
  EOT
}
