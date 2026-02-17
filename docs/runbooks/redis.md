# Runbook Redis Sentinel

## Informations service

| Champ | Valeur |
|-------|--------|
| Namespace | `production` |
| StatefulSet | `redis` |
| Replicas | 2 (master + replica) |
| Sentinel | 3 instances (quorum 2) |
| Port | 6379 (data), 26379 (sentinel) |
| Version | Redis 7.2 |
| Persistance | RDB snapshots + AOF |

## Commandes courantes

### Vérifier l'état

```bash
# Info réplication master
kubectl exec -n production redis-0 -- redis-cli info replication

# Statut Sentinel
kubectl exec -n production redis-0 -- redis-cli -p 26379 sentinel masters

# Sentinels connus
kubectl exec -n production redis-0 -- redis-cli -p 26379 sentinel sentinels mymaster
```

### Connexion directe

```bash
kubectl exec -it -n production redis-0 -- redis-cli
kubectl exec -it -n production redis-1 -- redis-cli
```

## Procédures opérationnelles

### Failover manuel

```bash
# Forcer un failover via Sentinel
kubectl exec -n production redis-0 -- redis-cli -p 26379 sentinel failover mymaster

# Vérifier le nouveau master
kubectl exec -n production redis-0 -- redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

### Flush cache (attention!)

```bash
# Flush une seule DB
kubectl exec -n production redis-0 -- redis-cli -n 0 flushdb

# Flush tout (DANGER - seulement si nécessaire)
kubectl exec -n production redis-0 -- redis-cli flushall
```

## Alertes

| Alerte | Seuil | Action |
|--------|-------|--------|
| RedisDown | Instance indisponible | Vérifier pod, restart |
| RedisMemoryHigh | > 90% maxmemory | Vérifier eviction policy, augmenter mémoire |
| RedisMasterLinkDown | Réplication cassée | Vérifier réseau, resync |
| RedisKeyEviction | > 100 keys/min | Revoir TTL, augmenter mémoire |

## Troubleshooting

### Mémoire saturée

```bash
# Vérifier utilisation mémoire
kubectl exec -n production redis-0 -- redis-cli info memory

# Analyser les clés volumineuses
kubectl exec -n production redis-0 -- redis-cli --bigkeys
```

### Réplication cassée

```bash
# Forcer resync complet
kubectl exec -n production redis-1 -- redis-cli replicaof no one
kubectl exec -n production redis-1 -- redis-cli replicaof redis-0.redis.production.svc.cluster.local 6379
```
