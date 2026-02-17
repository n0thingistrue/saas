# Databases - PostgreSQL Patroni + Redis Sentinel

## Architecture HA

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRODUCTION                                │
│                                                                  │
│  ┌─── Node 1 (32GB) ──────────┐  ┌─── Node 2 (16GB) ────────┐ │
│  │                             │  │                           │ │
│  │  ┌─────────────────────┐   │  │  ┌─────────────────────┐ │ │
│  │  │ PostgreSQL PRIMARY  │   │  │  │ PostgreSQL STANDBY  │ │ │
│  │  │ 3 vCPU / 8GB RAM   │◄──┼──┼──│ 2 vCPU / 4GB RAM   │ │ │
│  │  │ Patroni Leader      │   │  │  │ Patroni Replica     │ │ │
│  │  │ WAL-G → S3         │   │  │  │ Streaming Repl.     │ │ │
│  │  │ Port: 5432 / 8008  │   │  │  │ Port: 5432 / 8008  │ │ │
│  │  └─────────────────────┘   │  │  └─────────────────────┘ │ │
│  │                             │  │                           │ │
│  │  ┌────────┐ ┌────────┐    │  │  ┌────────┐              │ │
│  │  │ Redis  │ │ Redis  │    │  │  │ Redis  │              │ │
│  │  │ Master │ │ Replica│    │  │  │ Replica│              │ │
│  │  │ redis-0│ │ redis-1│    │  │  │ redis-2│              │ │
│  │  │+Sentinl│ │+Sentinl│    │  │  │+Sentinl│              │ │
│  │  └────────┘ └────────┘    │  │  └────────┘              │ │
│  └─────────────────────────────┘  └───────────────────────────┘ │
│                                                                  │
│  Services:                                                       │
│    postgresql-primary:5432  → Primary (RW)                      │
│    postgresql-replica:5432  → Standby (RO)                      │
│    redis-master:6379        → Master  (RW)                      │
│    redis-replica:6379       → Replicas (RO)                     │
│    redis-sentinel:26379     → Sentinel (discovery)              │
└─────────────────────────────────────────────────────────────────┘
```

## Structure des fichiers

```
kubernetes/databases/
├── postgresql/
│   ├── patroni-config.yaml         # Configuration Patroni (DCS, replication, tuning)
│   ├── postgresql-init.yaml        # Scripts init (users, DB, extensions, RGPD)
│   ├── statefulset.yaml            # StatefulSet 2 replicas + postgres_exporter
│   ├── services.yaml               # Headless + Primary RW + Replica RO
│   ├── credentials.yaml.example    # Template credentials (→ SealedSecret)
│   └── podmonitor.yaml             # Prometheus scraping + alertes
├── redis/
│   ├── redis-config.yaml           # redis.conf + script init master/replica
│   ├── redis-sentinel-config.yaml  # sentinel.conf + script init Sentinel
│   ├── statefulset.yaml            # StatefulSet 3 replicas + Sentinel + exporter
│   ├── services.yaml               # Headless + Master + Replica + Sentinel
│   ├── credentials.yaml.example    # Template credentials (→ SealedSecret)
│   └── podmonitor.yaml             # Prometheus scraping + alertes
└── backup/
    ├── postgresql-wal-backup.yaml  # CronJob WAL push (toutes les 15min)
    ├── postgresql-basebackup.yaml  # CronJob full backup (nightly 02h00)
    ├── redis-backup.yaml           # CronJob RDB snapshot (toutes les 6h)
    ├── s3-credentials.yaml.example # Credentials S3 Hetzner
    └── backup-scripts.yaml         # Scripts verify, restore, health report
```

## Deploiement

### Prerequis

1. Namespaces et RBAC crees (`kubectl apply -k kubernetes/base/`)
2. Sealed Secrets controller deploye
3. PV/PVC crees et volumes Hetzner montes

### 1. Creer les secrets (via kubeseal)

```bash
# PostgreSQL
kubectl create secret generic postgresql-credentials \
  --namespace production \
  --from-literal=POSTGRES_PASSWORD='VotreMotDePasseForT!' \
  --from-literal=POSTGRES_REPLICATION_PASSWORD='MotDePasseReplication!' \
  --from-literal=POSTGRES_APP_PASSWORD='MotDePasseApp!' \
  --from-literal=POSTGRES_READONLY_PASSWORD='MotDePasseReadOnly!' \
  --dry-run=client -o yaml | kubeseal --format yaml \
  > kubernetes/secrets/postgresql-sealed.yaml

# Redis
kubectl create secret generic redis-credentials \
  --namespace production \
  --from-literal=REDIS_PASSWORD='MotDePasseRedis!' \
  --dry-run=client -o yaml | kubeseal --format yaml \
  > kubernetes/secrets/redis-sealed.yaml

# S3 (dans production ET backup namespaces)
for NS in production backup; do
  kubectl create secret generic s3-credentials \
    --namespace $NS \
    --from-literal=AWS_ACCESS_KEY_ID='votre-access-key' \
    --from-literal=AWS_SECRET_ACCESS_KEY='votre-secret-key' \
    --from-literal=AWS_ENDPOINT='https://fsn1.your-objectstorage.com' \
    --from-literal=S3_BUCKET='saas-backups-prod' \
    --from-literal=WALG_S3_PREFIX='s3://saas-backups-prod/walg' \
    --dry-run=client -o yaml | kubeseal --format yaml \
    > kubernetes/secrets/s3-sealed-${NS}.yaml
done

# Appliquer les SealedSecrets
kubectl apply -f kubernetes/secrets/
```

### 2. Deployer PostgreSQL

```bash
kubectl apply -f kubernetes/databases/postgresql/
# Attendre que les 2 pods soient Ready
kubectl rollout status statefulset/postgresql -n production --timeout=300s
```

### 3. Deployer Redis

```bash
kubectl apply -f kubernetes/databases/redis/
kubectl rollout status statefulset/redis -n production --timeout=180s
```

### 4. Deployer les backups

```bash
kubectl apply -f kubernetes/databases/backup/
```

### 5. Verifier

```bash
# PostgreSQL - etat Patroni
kubectl exec -n production postgresql-0 -- patronictl list

# Redis - info replication
kubectl exec -n production redis-0 -- redis-cli -a $REDIS_PASSWORD info replication

# Sentinel - master actuel
kubectl exec -n production redis-0 -- redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

## Test de failover

### PostgreSQL - Failover Patroni

```bash
# 1. Verifier l'etat initial
kubectl exec -n production postgresql-0 -- patronictl list

# 2. Simuler une panne du primary
kubectl delete pod postgresql-0 -n production

# 3. Observer le failover (< 30s)
watch kubectl exec -n production postgresql-1 -- patronictl list

# 4. Le standby (postgresql-1) doit etre promu primary
# 5. Quand postgresql-0 redemarre, il rejoint comme standby

# Failover manuel (switchover)
kubectl exec -n production postgresql-0 -- patronictl switchover \
  --master postgresql-0 --candidate postgresql-1 --force
```

### Redis - Failover Sentinel

```bash
# 1. Verifier le master actuel
kubectl exec -n production redis-0 -- redis-cli -p 26379 \
  sentinel get-master-addr-by-name mymaster

# 2. Simuler une panne du master
kubectl delete pod redis-0 -n production

# 3. Observer le failover Sentinel (< 10s)
kubectl exec -n production redis-1 -- redis-cli -p 26379 \
  sentinel get-master-addr-by-name mymaster

# 4. Forcer un failover via Sentinel
kubectl exec -n production redis-0 -- redis-cli -p 26379 \
  sentinel failover mymaster
```

## Restore depuis backup

### PostgreSQL - Point-in-Time Recovery

```bash
# Lister les backups
kubectl exec -n production postgresql-0 -- wal-g backup-list

# Restore au dernier etat
kubectl exec -n backup <backup-pod> -- /scripts/restore-postgresql.sh latest

# Restore a un point precis (PITR)
kubectl exec -n backup <backup-pod> -- /scripts/restore-postgresql.sh \
  "2024-01-15 14:30:00" pitr
```

### Redis - Restore RDB

```bash
# Lister les snapshots S3
kubectl exec -n backup <backup-pod> -- /scripts/restore-redis.sh

# Restore le dernier snapshot
kubectl exec -n backup <backup-pod> -- /scripts/restore-redis.sh latest
```

## Troubleshooting

### PostgreSQL

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| Pod CrashLoopBackOff | `kubectl logs -n production postgresql-0 --previous` | Verifier permissions volume, credentials |
| Pas de primary | `kubectl exec -n production postgresql-0 -- patronictl list` | `patronictl failover --force` |
| Lag replication > 30s | `kubectl exec -n production postgresql-0 -- psql -c "SELECT * FROM pg_stat_replication;"` | Verifier reseau, IO disque |
| Split-brain (2 primaries) | `patronictl list` montre 2 leaders | `patronictl reinit <ancien-primary>` |
| OOM killed (Node 2) | `kubectl describe pod postgresql-1` | Reduire shared_buffers du standby |

### Redis

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| Pod CrashLoopBackOff | `kubectl logs -n production redis-0` | Verifier AOF corrompu, `redis-check-aof --fix` |
| Pas de master | `redis-cli -p 26379 sentinel masters` | `sentinel failover mymaster` |
| Replication cassee | `redis-cli info replication` | `replicaof <master-ip> 6379` |
| Memoire pleine | `redis-cli info memory` | Verifier eviction policy, analyser `--bigkeys` |
| Sentinel desynchronise | `redis-cli -p 26379 sentinel ckquorum mymaster` | Redemarrer les Sentinels un par un |

## Metriques a surveiller

### PostgreSQL
- `pg_stat_replication_lag` : lag replication (cible: < 1s)
- `pg_stat_activity_count` : connexions actives (max: 200)
- `pg_stat_database_xact_commit` : throughput transactions
- `pg_stat_database_deadlocks` : deadlocks (cible: 0)
- `pg_database_size_bytes` : taille base (alerte > 85%)

### Redis
- `redis_memory_used_bytes` : memoire utilisee (max: 1.5GB)
- `redis_connected_clients` : clients connectes
- `redis_keyspace_hits_total / misses_total` : hit ratio (cible: > 90%)
- `redis_connected_slaves` : replicas connectes (cible: 2)
- `redis_evicted_keys_total` : cles evincees (cible: faible)
