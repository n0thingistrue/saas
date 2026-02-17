# =============================================================================
# Volumes persistants - Hetzner Cloud
# =============================================================================
# Volumes bloc attachés aux serveurs pour les données stateful.
# Les volumes Hetzner sont répliqués (3 copies) et persistent indépendamment
# des serveurs, ce qui protège les données en cas de rebuild serveur.
#
# Ces volumes seront montés dans les pods K8s via des PersistentVolumes
# de type hostPath pointant vers le point de montage du volume.
# =============================================================================

# -----------------------------------------------------------------------------
# Volume PostgreSQL Primary (Node 1)
# Stocke les fichiers de données PostgreSQL (PGDATA)
# Taille initiale : 50 GB (extensible sans downtime)
# -----------------------------------------------------------------------------
resource "hcloud_volume" "postgresql_primary" {
  name      = "${local.name_prefix}-vol-pg-primary"
  size      = var.volume_postgresql_size
  server_id = hcloud_server.node1.id
  location  = var.location
  format    = "ext4"

  labels = merge(local.common_labels, {
    service = "postgresql"
    role    = "primary"
  })

  # Empêcher la suppression accidentelle des données
  delete_protection = var.environment == "prod" ? true : false

  lifecycle {
    # Ne pas détruire un volume contenant des données
    # Commenter pour terraform destroy complet
    # prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Volume PostgreSQL Standby (Node 2)
# Réplica streaming de PostgreSQL pour la haute disponibilité
# Même taille que le primary pour supporter un failover complet
# -----------------------------------------------------------------------------
resource "hcloud_volume" "postgresql_standby" {
  name      = "${local.name_prefix}-vol-pg-standby"
  size      = var.volume_postgresql_standby_size
  server_id = hcloud_server.node2.id
  location  = var.location
  format    = "ext4"

  labels = merge(local.common_labels, {
    service = "postgresql"
    role    = "standby"
  })

  delete_protection = var.environment == "prod" ? true : false
}

# -----------------------------------------------------------------------------
# Volume Redis (Node 1)
# Stocke les snapshots RDB et fichiers AOF
# Redis est principalement en mémoire, le volume sert à la persistance
# -----------------------------------------------------------------------------
resource "hcloud_volume" "redis" {
  name      = "${local.name_prefix}-vol-redis"
  size      = var.volume_redis_size
  server_id = hcloud_server.node1.id
  location  = var.location
  format    = "ext4"

  labels = merge(local.common_labels, {
    service = "redis"
    role    = "master"
  })
}

# -----------------------------------------------------------------------------
# Volume Samba-AD (Node 1)
# Stocke la base de données AD (sam.ldb), SYSVOL, et la configuration
# Données critiques pour l'authentification
# -----------------------------------------------------------------------------
resource "hcloud_volume" "samba" {
  name      = "${local.name_prefix}-vol-samba"
  size      = var.volume_samba_size
  server_id = hcloud_server.node1.id
  location  = var.location
  format    = "ext4"

  labels = merge(local.common_labels, {
    service = "samba-ad"
    role    = "primary"
  })

  delete_protection = var.environment == "prod" ? true : false
}

# -----------------------------------------------------------------------------
# Volume Monitoring (Node 1)
# Stocke les données Prometheus (TSDB), Grafana (sqlite), Loki (chunks)
# 30 GB pour ~30 jours de rétention métriques
# -----------------------------------------------------------------------------
resource "hcloud_volume" "monitoring" {
  name      = "${local.name_prefix}-vol-monitoring"
  size      = var.volume_monitoring_size
  server_id = hcloud_server.node1.id
  location  = var.location
  format    = "ext4"

  labels = merge(local.common_labels, {
    service = "monitoring"
  })
}
