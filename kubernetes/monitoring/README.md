# Monitoring Stack

## Architecture

```
                    ┌──────────────────────────┐
                    │      Grafana 10.4         │
                    │    monitoring.saas.local   │
                    │                            │
                    │  ┌─────────┐ ┌──────────┐ │
                    │  │Dashboards│ │Alerting  │ │
                    │  │(5 custom)│ │(visual)  │ │
                    │  └────┬────┘ └────┬─────┘ │
                    └───────┼───────────┼───────┘
                            │           │
               ┌────────────┤           │
               ▼            ▼           │
    ┌──────────────┐  ┌──────────┐      │
    │  Prometheus   │  │   Loki   │      │
    │   v2.50       │  │  v2.9    │      │
    │  TSDB 15d     │  │ Logs 15d │      │
    │  15GB PVC     │  │ 10GB PVC │      │
    └──────┬───────┘  └────┬─────┘      │
           │               │            │
    ┌──────┼───────────────┼────┐       │
    │      │  Scrape       │    │       │
    │      ▼               ▼    │       ▼
    │ ┌─────────┐   ┌─────────┐ │ ┌──────────────┐
    │ │  Node   │   │Promtail │ │ │ AlertManager │
    │ │Exporter │   │DaemonSet│ │ │    v0.27     │
    │ │DaemonSet│   │(logs)   │ │ │              │
    │ └─────────┘   └─────────┘ │ │ Slack/Email/ │
    │                           │ │ PagerDuty    │
    │  Tous les nodes (2)       │ └──────────────┘
    └───────────────────────────┘
```

## Composants

| Composant | Version | Replicas | Node | Stockage |
|-----------|---------|----------|------|----------|
| Prometheus | v2.50 | 1 | Node 1 | PVC 15GB |
| Grafana | 10.4 | 1 | Node 1 | PVC 5GB |
| Loki | v2.9 | 1 | Node 1 | PVC 10GB |
| Promtail | v2.9 | DaemonSet (2) | Tous | emptyDir |
| Node Exporter | v1.7 | DaemonSet (2) | Tous | - |
| AlertManager | v0.27 | 1 | Node 1 | emptyDir |

## Metriques collectees

| Source | Job | Metriques |
|--------|-----|-----------|
| Kubelet | kubernetes-nodes | node_*, kubelet_* |
| cAdvisor | kubernetes-cadvisor | container_cpu_*, container_memory_* |
| Pods | kubernetes-pods | Via annotations prometheus.io/* |
| PostgreSQL | postgresql | pg_stat_*, pg_replication_* |
| Redis | redis | redis_memory_*, redis_commands_* |
| Traefik | traefik | traefik_service_*, traefik_entrypoint_* |
| Node Exporter | node-exporter | node_cpu_*, node_memory_*, node_disk_* |
| AlertManager | alertmanager | alertmanager_* |

## Dashboards Grafana

| Dashboard | UID | Description |
|-----------|-----|-------------|
| Infrastructure | infra-k3s-cluster | CPU/Memory/Disk nodes, Top pods, Pod count |
| PostgreSQL | postgresql-patroni | Connections, transactions, replication lag, cache hit |
| Redis | redis-sentinel | Memory, hit rate, commands/s, evictions, keyspace |
| Applications | applications-saas | Backend req/s, errors, latency p50/p95/p99, Frontend SSR |
| Traefik | traefik-ingress | Requests by service, status codes, cert expiry, connections |

## Alertes configurees

### Infrastructure
| Alerte | Severity | Condition | For |
|--------|----------|-----------|-----|
| NodeDown | critical | up == 0 | 2m |
| NodeHighCPU | warning | CPU > 80% | 10m |
| NodeCriticalCPU | critical | CPU > 95% | 5m |
| NodeHighMemory | warning | Mem > 85% | 5m |
| NodeCriticalMemory | critical | Mem > 95% | 2m |
| NodeDiskHigh | warning | Disk > 80% | 10m |
| NodeDiskCritical | critical | Disk > 90% | 5m |
| PodCrashLooping | warning | > 5 restarts/h | 0m |
| PodPending | warning | Pending | 5m |

### Databases
| Alerte | Severity | Condition | For |
|--------|----------|-----------|-----|
| PostgreSQLDown | critical | pg_up == 0 | 1m |
| PostgreSQLNoPrimary | critical | No primary | 1m |
| PostgreSQLReplicationLag | warning | Lag > 30s | 2m |
| PostgreSQLReplicationLagCritical | critical | Lag > 5min | 1m |
| PostgreSQLTooManyConnections | warning | > 80% max | 5m |
| RedisDown | critical | redis_up == 0 | 1m |
| RedisMasterDown | critical | No master | 1m |
| RedisMemoryHigh | warning | Mem > 90% | 5m |
| RedisMemoryCritical | critical | Mem > 98% | 2m |

### Applications
| Alerte | Severity | Condition | For |
|--------|----------|-----------|-----|
| BackendDown | critical | No pods up | 1m |
| FrontendDown | critical | No pods up | 1m |
| HighErrorRate | critical | 5xx > 5% | 2m |
| HighLatencyP95 | warning | p95 > 500ms | 5m |

### Ingress + Samba-AD
| Alerte | Severity | Condition | For |
|--------|----------|-----------|-----|
| TraefikDown | critical | up == 0 | 1m |
| CertExpiringSoon | warning | < 7 jours | 1h |
| TraefikHighErrorRate | critical | 5xx > 5% | 2m |
| SambaADDown | critical | No running pod | 1m |
| SambaADNotReady | warning | Not ready | 2m |

## Deploiement

```bash
# 1. Deployer la stack monitoring
kubectl apply -k kubernetes/monitoring/

# 2. Verifier les pods
kubectl get pods -n monitoring

# 3. Verifier Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Ouvrir http://localhost:9090/targets

# 4. Verifier Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Ouvrir http://localhost:3000 (admin / mot de passe du secret)

# 5. Verifier Loki
kubectl port-forward -n monitoring svc/loki 3100:3100
curl http://localhost:3100/ready

# 6. Verifier AlertManager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Ouvrir http://localhost:9093
```

## Acces Grafana

- **URL** : https://monitoring.saas.local
- **User** : admin
- **Password** : defini dans `grafana-secrets` (Secret Kubernetes)

## Exemples PromQL utiles

```promql
# CPU moyen par node (5min)
instance:node_cpu_utilisation:rate5m

# Memoire libre par node
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Requetes/s backend
sum(rate(http_requests_total{namespace="production", container="backend"}[5m]))

# Taux erreurs 5xx backend
sum(rate(http_requests_total{namespace="production", container="backend", status=~"5.."}[5m]))
/ sum(rate(http_requests_total{namespace="production", container="backend"}[5m])) * 100

# Latence p95 backend
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{container="backend"}[5m])) by (le))

# PostgreSQL replication lag
pg_replication_lag

# Redis memory usage %
redis_memory_used_bytes / redis_memory_max_bytes * 100

# Top 5 pods by CPU
topk(5, sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod))

# Traefik requests par service
sum(rate(traefik_service_requests_total[5m])) by (service)

# Certificats TLS - jours avant expiration
(traefik_tls_certs_not_after - time()) / 86400
```

## Exemples LogQL utiles (Loki)

```logql
# Tous les logs du backend
{namespace="production", app="backend"}

# Erreurs backend
{namespace="production", app="backend"} |= "error"

# Logs JSON parses avec filtre level
{namespace="production", app="backend"} | json | level="error"

# Slow requests backend (> 500ms)
{namespace="production", app="backend"} | json | latency > 500

# Logs Traefik status 5xx
{namespace="ingress", app="traefik"} | json | status >= 500

# Logs Samba-AD
{namespace="production", app="samba-ad"}

# Volume de logs par app (rate)
sum(rate({namespace="production"}[5m])) by (app)
```

## Retention des donnees

| Composant | Retention | Stockage |
|-----------|-----------|----------|
| Prometheus TSDB | 15 jours | 15GB PVC |
| Loki logs | 15 jours | 10GB PVC |
| AlertManager | En memoire | emptyDir |
| Grafana dashboards | Permanent (ConfigMaps) | 5GB PVC |

## Troubleshooting

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| Prometheus target down | `kubectl port-forward svc/prometheus 9090` → Targets | Verifier pods, network policies, ports |
| Scrape errors | Prometheus UI → Targets → Error | Verifier annotations, endpoint, RBAC |
| Loki logs pas visibles | `curl loki:3100/ready` | Verifier Promtail DaemonSet, volumes hostPath |
| Grafana datasource down | Grafana → Settings → Data Sources → Test | Verifier services Prometheus/Loki |
| AlertManager pas de notification | `curl alertmanager:9093/api/v2/alerts` | Verifier secret Slack webhook, config route |
| Dashboard vide | Verifier datasource UID dans JSON | Utiliser variable ${DS_PROMETHEUS} |
| Prometheus OOM | `kubectl describe pod prometheus-0` | Augmenter memory limits, reduire retention |
| Disque plein Prometheus | `kubectl exec prometheus-0 -- df -h` | Reduire retention, augmenter PVC |
