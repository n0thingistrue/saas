# Backup & Recovery

## Vue d'ensemble

Stratégie de sauvegarde multi-niveaux pour garantir RPO < 15 minutes :

| Type | Outil | Fréquence | Rétention | Destination |
|------|-------|-----------|-----------|-------------|
| PostgreSQL WAL | WAL-G | Continu (streaming) | 30 jours | Hetzner S3 |
| PostgreSQL Full | WAL-G base backup | Quotidien 02h00 | 12 mois | Hetzner S3 + Backblaze B2 |
| Redis RDB | Snapshot | Toutes les 15 min | 7 jours | Volume local + S3 |
| Volumes K8s | Hetzner Snapshots | Quotidien 03h00 | 30 jours | Hetzner |
| Config Samba-AD | samba-tool backup | Quotidien 04h00 | 90 jours | S3 |
| Cluster etcd | K3s auto-snapshot | Toutes les 12h | 7 jours | Local + S3 |

## Politique de rétention

```
Quotidien  : 30 jours (daily à 02h00 UTC)
Hebdomadaire : 12 semaines (dimanche 02h00 UTC)
Mensuel    : 12 mois (1er du mois 02h00 UTC)
```

## Structure

```
backup/
├── walg/                       # Configuration WAL-G
│   ├── walg-config.yaml        # ConfigMap WAL-G
│   └── walg-secret.yaml        # Sealed credentials S3
├── scripts/
│   ├── backup-postgresql.sh    # Backup manuel PostgreSQL
│   ├── backup-redis.sh         # Backup manuel Redis
│   ├── backup-volumes.sh       # Snapshot volumes Hetzner
│   ├── backup-samba.sh         # Backup Samba-AD
│   ├── restore-postgresql.sh   # Restore PostgreSQL
│   ├── restore-redis.sh        # Restore Redis
│   └── restore-full.sh         # Restore complète (DR)
└── cronjobs/
    ├── cronjob-pg-backup.yaml  # CronJob backup PostgreSQL
    ├── cronjob-redis.yaml      # CronJob backup Redis
    └── cronjob-volumes.yaml    # CronJob snapshots volumes
```

## Restore

### PostgreSQL (Point-in-Time Recovery)

```bash
# Lister les backups disponibles
./scripts/backup-postgresql.sh --list

# Restore au dernier état
./scripts/restore-postgresql.sh --latest

# Restore à un point précis
./scripts/restore-postgresql.sh --target-time "2024-01-15 14:30:00"
```

### Disaster Recovery complète

```bash
# Restore complète infrastructure
./scripts/restore-full.sh --env production --from-backup latest
```

## Tests DR

Les tests de disaster recovery sont exécutés mensuellement :
```bash
cd scripts/disaster-recovery
./test-dr.sh --env staging
```
