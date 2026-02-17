# Runbook PostgreSQL Patroni

## Informations service

| Champ | Valeur |
|-------|--------|
| Namespace | `production` |
| StatefulSet | `postgresql` |
| Replicas | 2 (primary + standby) |
| Port | 5432 |
| Version | PostgreSQL 16 |
| HA | Patroni + streaming replication |
| Backup | WAL-G → Hetzner S3 |

## Commandes courantes

### Vérifier l'état du cluster Patroni

```bash
kubectl exec -n production postgresql-0 -- patronictl list
```

Sortie attendue :
```
+ Cluster: postgresql (7xxx) ---+----+-----------+
| Member        | Host     | Role    | State     |
+---------------+----------+---------+-----------+
| postgresql-0  | 10.42.x  | Leader  | running   |
| postgresql-1  | 10.42.x  | Replica | streaming |
+---------------+----------+---------+-----------+
```

### Vérifier le lag de réplication

```bash
kubectl exec -n production postgresql-0 -- psql -U postgres -c \
  "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
   (sent_lsn - replay_lsn) AS lag
   FROM pg_stat_replication;"
```

### Connexion directe

```bash
# Primary
kubectl exec -it -n production postgresql-0 -- psql -U postgres

# Standby
kubectl exec -it -n production postgresql-1 -- psql -U postgres
```

## Procédures opérationnelles

### Failover manuel

```bash
# Promouvoir le standby en primary
kubectl exec -n production postgresql-0 -- patronictl failover --master postgresql-0 --candidate postgresql-1 --force

# Vérifier le nouveau leader
kubectl exec -n production postgresql-0 -- patronictl list
```

### Switchover planifié (maintenance)

```bash
# Switchover gracieux (sans perte de données)
kubectl exec -n production postgresql-0 -- patronictl switchover --master postgresql-0 --candidate postgresql-1 --force
```

### Backup manuel

```bash
kubectl exec -n production postgresql-0 -- wal-g backup-push /var/lib/postgresql/data
kubectl exec -n production postgresql-0 -- wal-g backup-list
```

### Restore (Point-in-Time Recovery)

```bash
# 1. Arrêter l'application (scale down backend)
kubectl scale deployment backend -n production --replicas=0

# 2. Exécuter le restore
./scripts/backup/restore-postgresql.sh --target-time "2024-01-15 14:30:00"

# 3. Vérifier les données
kubectl exec -it -n production postgresql-0 -- psql -U postgres -c "SELECT count(*) FROM users;"

# 4. Redémarrer l'application
kubectl scale deployment backend -n production --replicas=3
```

## Alertes

| Alerte | Seuil | Action |
|--------|-------|--------|
| PostgresqlDown | Instance indisponible | Vérifier pod, restart si nécessaire |
| PostgresqlReplicationLag | Lag > 30s | Vérifier réseau, IO disque |
| PostgresqlReplicationLag | Lag > 300s | Failover potentiel, investiguer |
| PostgresqlTooManyConnections | > 80% max_connections | Vérifier connection pooling |
| PostgresqlDeadLocks | > 5/min | Analyser queries, optimiser |
| PostgresqlDiskSpace | > 85% | Nettoyer WAL, étendre volume |

## Troubleshooting

### Pod en CrashLoopBackOff

```bash
# Vérifier les logs
kubectl logs -n production postgresql-0 --previous

# Causes fréquentes :
# - Volume plein → étendre le PV
# - Configuration incorrecte → vérifier ConfigMap
# - Permissions → vérifier securityContext
```

### Réplication cassée

```bash
# Réinitialiser le standby
kubectl exec -n production postgresql-1 -- patronictl reinit postgresql postgresql-1 --force
```

### Performance dégradée

```bash
# Queries lentes
kubectl exec -n production postgresql-0 -- psql -U postgres -c \
  "SELECT pid, now() - pg_stat_activity.query_start AS duration, query
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY duration DESC
   LIMIT 10;"
```
