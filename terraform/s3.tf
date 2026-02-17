# =============================================================================
# Object Storage S3 - Hetzner Cloud
# =============================================================================
# Hetzner Object Storage (compatible S3) pour les backups :
#   - WAL-G : archivage continu des WAL PostgreSQL (RPO < 15 min)
#   - Base backups PostgreSQL (quotidien)
#   - Snapshots Redis RDB
#   - Backups Samba-AD
#   - Exports métriques et rapports
#
# Note : Hetzner Object Storage est compatible avec l'API S3 d'AWS.
# Les outils comme WAL-G, aws-cli, s3cmd fonctionnent nativement.
#
# Important : Au moment de l'écriture, l'Object Storage Hetzner
# se gère via l'API Hetzner ou la console (pas encore de ressource
# Terraform native). On utilise un script d'initialisation à la place.
# =============================================================================

# -----------------------------------------------------------------------------
# Génération du script d'initialisation S3
# Ce script crée le bucket et configure les credentials
# À exécuter une seule fois après terraform apply
# -----------------------------------------------------------------------------
resource "local_file" "s3_init_script" {
  filename        = "${path.module}/../scripts/utils/init-s3-storage.sh"
  file_permission = "0755"

  content = <<-SCRIPT
    #!/usr/bin/env bash
    # ==========================================================================
    # Initialisation Hetzner Object Storage
    # ==========================================================================
    # Ce script configure l'Object Storage S3 pour les backups.
    # À exécuter une seule fois après le provisionnement Terraform.
    #
    # Prérequis : aws-cli ou s3cmd installé
    # ==========================================================================
    set -euo pipefail

    # Configuration
    S3_ENDPOINT="https://fsn1.your-objectstorage.com"
    BUCKET_NAME="${var.s3_bucket_name}"

    echo "=== Initialisation Object Storage Hetzner ==="
    echo ""
    echo "IMPORTANT: Créez les credentials S3 dans la console Hetzner :"
    echo "  1. Connectez-vous à https://console.hetzner.cloud"
    echo "  2. Allez dans Object Storage → Manage credentials"
    echo "  3. Générez un Access Key + Secret Key"
    echo "  4. Configurez aws-cli avec ces credentials :"
    echo ""
    echo "    aws configure --profile hetzner"
    echo "    AWS Access Key ID: <votre-access-key>"
    echo "    AWS Secret Access Key: <votre-secret-key>"
    echo "    Default region name: fsn1"
    echo "    Default output format: json"
    echo ""
    read -p "Appuyez sur Entrée une fois les credentials configurés..."

    # Créer le bucket principal
    echo "[1/4] Création du bucket: $BUCKET_NAME"
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --endpoint-url "$S3_ENDPOINT" \
      --profile hetzner 2>/dev/null || echo "  → Bucket existe déjà"

    # Créer les préfixes (dossiers virtuels)
    echo "[2/4] Création de la structure de dossiers..."
    for prefix in walg/wal walg/basebackups redis/snapshots samba/backups etcd/snapshots reports; do
      aws s3api put-object \
        --bucket "$BUCKET_NAME" \
        --key "$prefix/" \
        --endpoint-url "$S3_ENDPOINT" \
        --profile hetzner
      echo "  → $prefix/"
    done

    # Configurer la politique de lifecycle (rétention automatique)
    echo "[3/4] Configuration de la politique de rétention..."
    cat > /tmp/lifecycle-policy.json << 'EOF'
    {
      "Rules": [
        {
          "ID": "cleanup-old-wal",
          "Status": "Enabled",
          "Filter": {
            "Prefix": "walg/wal/"
          },
          "Expiration": {
            "Days": 30
          }
        },
        {
          "ID": "cleanup-old-basebackups",
          "Status": "Enabled",
          "Filter": {
            "Prefix": "walg/basebackups/"
          },
          "Expiration": {
            "Days": 365
          }
        },
        {
          "ID": "cleanup-old-redis",
          "Status": "Enabled",
          "Filter": {
            "Prefix": "redis/snapshots/"
          },
          "Expiration": {
            "Days": 7
          }
        }
      ]
    }
    EOF

    aws s3api put-bucket-lifecycle-configuration \
      --bucket "$BUCKET_NAME" \
      --lifecycle-configuration file:///tmp/lifecycle-policy.json \
      --endpoint-url "$S3_ENDPOINT" \
      --profile hetzner 2>/dev/null || echo "  → Lifecycle non supporté (ok)"

    rm -f /tmp/lifecycle-policy.json

    echo "[4/4] Vérification..."
    aws s3 ls "s3://$BUCKET_NAME/" \
      --endpoint-url "$S3_ENDPOINT" \
      --profile hetzner

    echo ""
    echo "=== Object Storage initialisé avec succès ==="
    echo ""
    echo "Endpoint S3   : $S3_ENDPOINT"
    echo "Bucket        : $BUCKET_NAME"
    echo ""
    echo "Prochaine étape : configurer les secrets WAL-G dans Kubernetes"
    echo "  → Voir backup/walg/walg-secret.yaml"
  SCRIPT
}

# -----------------------------------------------------------------------------
# Variables S3 exportées pour les autres composants
# Utilisées par les scripts de backup et les ConfigMaps K8s
# -----------------------------------------------------------------------------
resource "local_file" "s3_env" {
  filename        = "${path.module}/../scripts/utils/.s3-env"
  file_permission = "0600"

  content = <<-ENV
    # Variables S3 générées par Terraform - NE PAS COMMITER
    export S3_ENDPOINT="https://fsn1.your-objectstorage.com"
    export S3_BUCKET="${var.s3_bucket_name}"
    export S3_REGION="fsn1"
    export WALG_S3_PREFIX="s3://${var.s3_bucket_name}/walg"
  ENV
}
