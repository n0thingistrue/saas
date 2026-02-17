# Scripts d'automatisation

## Vue d'ensemble

Scripts Bash pour l'installation, le déploiement, les tests et la maintenance.

## Structure

```
scripts/
├── install/                        # Installation K3s
│   ├── 00-prereqs.sh               # Prérequis système (packages, kernel)
│   ├── 01-install-k3s-server.sh    # K3s server (Node 1 - control plane)
│   ├── 02-install-k3s-agent.sh     # K3s agent (Node 2 - worker)
│   └── 03-post-install.sh          # Vérifications post-installation
├── bootstrap/
│   ├── bootstrap.sh                # Bootstrap complet (orchestrateur)
│   ├── 01-namespaces.sh            # Création namespaces + RBAC
│   ├── 02-sealed-secrets.sh        # Installation Sealed Secrets
│   ├── 03-cert-manager.sh          # Installation cert-manager
│   ├── 04-traefik.sh               # Configuration Traefik + WAF
│   ├── 05-postgresql.sh            # Déploiement PostgreSQL Patroni
│   ├── 06-redis.sh                 # Déploiement Redis Sentinel
│   ├── 07-samba-ad.sh              # Déploiement Samba-AD
│   ├── 08-backend.sh               # Déploiement NestJS
│   ├── 09-frontend.sh              # Déploiement Next.js
│   ├── 10-monitoring.sh            # Déploiement monitoring stack
│   ├── 11-security.sh              # Déploiement Wazuh + fail2ban
│   └── 12-argocd.sh                # Déploiement ArgoCD
├── testing/
│   ├── run-load-test.sh            # Lancement tests k6
│   ├── k6-scenarios/               # Scénarios k6
│   │   ├── smoke.js                # Test smoke (baseline)
│   │   ├── load.js                 # Test charge normale
│   │   ├── stress.js               # Test stress (limites)
│   │   └── soak.js                 # Test endurance (stabilité)
│   └── results/                    # Résultats (gitignored)
├── disaster-recovery/
│   ├── test-dr.sh                  # Test DR complet
│   ├── test-failover-pg.sh         # Test failover PostgreSQL
│   ├── test-failover-redis.sh      # Test failover Redis
│   └── test-node-failure.sh        # Test perte d'un node
├── compliance/
│   ├── generate-report.sh          # Génération rapport compliance
│   ├── check-iso27001.sh           # Vérification contrôles ISO 27001
│   ├── check-rgpd.sh              # Vérification conformité RGPD
│   └── reports/                    # Rapports générés (gitignored)
└── utils/
    ├── rotate-secrets.sh           # Rotation des secrets
    ├── update-certificates.sh      # Renouvellement certificats
    ├── cleanup-resources.sh        # Nettoyage ressources orphelines
    └── export-metrics.sh           # Export métriques pour rapports
```

## Utilisation

Tous les scripts sont exécutables et incluent un `--help` :

```bash
# Installation complète
./scripts/install/00-prereqs.sh
./scripts/install/01-install-k3s-server.sh
./scripts/install/02-install-k3s-agent.sh

# Bootstrap automatique
./scripts/bootstrap/bootstrap.sh --env production

# Tests
./scripts/testing/run-load-test.sh --scenario load
./scripts/disaster-recovery/test-dr.sh --env staging
```
