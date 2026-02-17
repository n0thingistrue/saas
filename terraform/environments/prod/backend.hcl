# =============================================================================
# Backend Configuration - Production
# =============================================================================
# Pour utiliser un backend distant S3 (recommandé en production) :
#   terraform init -backend-config=environments/prod/backend.hcl
#
# Décommenter le bloc backend "s3" dans main.tf avant utilisation.
# =============================================================================

# bucket   = "saas-terraform-state"
# key      = "prod/terraform.tfstate"
# region   = "fsn1"
# endpoint = "https://fsn1.your-objectstorage.com"

# Pour le développement initial, le state local est utilisé.
# Migrer vers un backend distant avant la mise en production multi-opérateurs.
