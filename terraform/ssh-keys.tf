# =============================================================================
# Clés SSH - Hetzner Cloud
# =============================================================================
# La clé SSH est utilisée pour l'accès initial aux serveurs.
# Elle doit être préalablement uploadée dans la console Hetzner.
#
# Sécurité :
#   - Authentification par mot de passe désactivée (via cloud-init)
#   - Seule l'authentification par clé est autorisée
#   - MaxAuthTries limité à 3 (via cloud-init)
# =============================================================================

# La data source dans main.tf récupère la clé existante :
# data "hcloud_ssh_key" "default" { name = var.ssh_key_name }

# Décommenter ci-dessous pour uploader une nouvelle clé via Terraform
# (utile si la clé n'est pas encore dans Hetzner)
#
# resource "hcloud_ssh_key" "default" {
#   name       = var.ssh_key_name
#   public_key = file(var.ssh_public_key_path)
#   labels     = local.common_labels
# }
