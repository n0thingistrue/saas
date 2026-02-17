# GitHub Actions CI/CD

## Pipelines

| Workflow | Trigger | Description |
|----------|---------|-------------|
| `ci.yml` | Push/PR sur main | Lint, tests, security scan |
| `cd-staging.yml` | Merge sur develop | Déploiement auto staging |
| `cd-production.yml` | Release tag | Déploiement prod (manual approval) |
| `security-scan.yml` | Cron quotidien | Scan Trivy + OWASP |
| `backup-check.yml` | Cron hebdomadaire | Vérification intégrité backups |

## Secrets GitHub requis

| Secret | Description |
|--------|-------------|
| `HCLOUD_TOKEN` | API Token Hetzner Cloud |
| `KUBECONFIG` | Kubeconfig du cluster K3s |
| `DOCKER_USERNAME` | Registry username |
| `DOCKER_PASSWORD` | Registry password |
| `ARGOCD_TOKEN` | Token ArgoCD pour sync |
| `SLACK_WEBHOOK` | Webhook notifications Slack |
