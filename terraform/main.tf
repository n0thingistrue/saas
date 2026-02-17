# =============================================================================
# Main Configuration - Infrastructure SaaS Hetzner Cloud
# =============================================================================
# Point d'entrée principal Terraform. Orchestre les modules et ressources.
#
# Architecture :
#   - 2 serveurs dédiés (CCX33 + CCX23) dans le même datacenter
#   - Réseau privé isolé pour le trafic inter-nodes
#   - Floating IP pour haute disponibilité
#   - Load Balancer pour répartition du trafic HTTPS
#   - Volumes persistants pour les données stateful
#   - Object Storage S3 pour les backups
#   - Firewall restrictif par rôle
#
# Utilisation :
#   terraform init
#   terraform plan -var-file=environments/prod/terraform.tfvars
#   terraform apply -var-file=environments/prod/terraform.tfvars
# =============================================================================

# -----------------------------------------------------------------------------
# Backend Configuration (state remote)
# Pour production, utiliser un backend distant (S3, Consul, etc.)
# En développement, le state local est suffisant.
# -----------------------------------------------------------------------------
# Décommenter pour backend distant :
# terraform {
#   backend "s3" {
#     # Configuration dans environments/<env>/backend.hcl
#   }
# }

# -----------------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------------

# Récupérer la clé SSH existante dans Hetzner
data "hcloud_ssh_key" "default" {
  name = var.ssh_key_name
}

# -----------------------------------------------------------------------------
# Locals - Valeurs calculées
# -----------------------------------------------------------------------------

locals {
  # Préfixe de nommage pour toutes les ressources
  name_prefix = "${var.project_name}-${var.environment}"

  # Labels enrichis avec l'environnement courant
  common_labels = merge(var.labels, {
    environment = var.environment
  })

  # Cloud-init pour la configuration initiale des serveurs
  # Installe les prérequis nécessaires à K3s et aux outils de sécurité
  cloud_init_base = <<-EOT
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - curl
      - wget
      - gnupg2
      - apt-transport-https
      - ca-certificates
      - software-properties-common
      - wireguard
      - fail2ban
      - ufw
      - jq
      - htop
      - iotop
      - net-tools
      - open-iscsi
      - nfs-common
      - unattended-upgrades
    # Paramètres kernel pour K3s et performances réseau
    write_files:
      - path: /etc/sysctl.d/99-kubernetes.conf
        content: |
          # Forwarding requis pour K3s
          net.ipv4.ip_forward = 1
          net.ipv6.conf.all.forwarding = 1
          # Performances réseau
          net.core.somaxconn = 65535
          net.ipv4.tcp_max_syn_backlog = 65535
          net.core.netdev_max_backlog = 65535
          # Connexions réseau
          net.ipv4.ip_local_port_range = 1024 65535
          net.ipv4.tcp_tw_reuse = 1
          # Mémoire réseau
          net.core.rmem_max = 16777216
          net.core.wmem_max = 16777216
          # inotify pour monitoring
          fs.inotify.max_user_watches = 524288
          fs.inotify.max_user_instances = 512
          # Sécurité réseau
          net.ipv4.conf.all.rp_filter = 1
          net.ipv4.conf.default.rp_filter = 1
          net.ipv4.icmp_echo_ignore_broadcasts = 1
          net.ipv4.conf.all.accept_redirects = 0
          net.ipv4.conf.default.accept_redirects = 0
          net.ipv4.conf.all.send_redirects = 0
          net.ipv4.conf.default.send_redirects = 0
      - path: /etc/modules-load.d/k3s.conf
        content: |
          br_netfilter
          overlay
          ip_tables
          iptable_filter
          iptable_nat
      - path: /etc/ssh/sshd_config.d/hardening.conf
        content: |
          PermitRootLogin prohibit-password
          PasswordAuthentication no
          X11Forwarding no
          MaxAuthTries 3
          ClientAliveInterval 300
          ClientAliveCountMax 2
    runcmd:
      - sysctl --system
      - modprobe br_netfilter
      - modprobe overlay
      - systemctl enable --now fail2ban
      - systemctl restart sshd
  EOT
}
