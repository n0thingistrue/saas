# Monitoring Stack

## Vue d'ensemble

Stack d'observabilité complète déployée dans le namespace `monitoring` :
- **Prometheus** : Métriques infrastructure et applicatives
- **Grafana** : Visualisation et dashboards
- **Loki** : Agrégation de logs
- **Promtail** : Collecte de logs depuis les nodes
- **AlertManager** : Gestion des alertes
- **Wazuh** : SIEM léger (détection intrusion)

## Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│  Promtail   │───►│     Loki     │◄───│   Grafana   │
│  (DaemonSet)│    │  (log store) │    │ (dashboards)│
└─────────────┘    └──────────────┘    └──────┬──────┘
                                              │
┌─────────────┐    ┌──────────────┐           │
│ ServiceMon. │───►│  Prometheus  │───────────┘
│  (targets)  │    │  (metrics)   │
└─────────────┘    └──────┬───────┘
                          │
                   ┌──────┴───────┐
                   │ AlertManager │──► Email/Slack/Webhook
                   └──────────────┘
```

## Dashboards Grafana

| Dashboard | Description |
|-----------|-------------|
| Cluster Overview | Santé globale K3s (CPU, RAM, disk, pods) |
| Application Metrics | Latence, throughput, erreurs (RED) |
| PostgreSQL | Connections, replication lag, queries |
| Redis | Memory, hit ratio, connections |
| Security | Alertes Wazuh, fail2ban, accès suspects |
| SLA Report | Uptime, disponibilité, SLA tracking |

## Alertes critiques

- Node down / NotReady
- Pod CrashLoopBackOff
- PostgreSQL replication lag > 30s
- Redis master down
- Certificat TLS expire < 14 jours
- Disk usage > 85%
- Memory usage > 90%
- HTTP 5xx rate > 5%

## Ressources allouées

Déployé sur **Node 1** (affinité) :
- Prometheus : 0.5 vCPU, 2GB RAM
- Grafana : 0.2 vCPU, 512MB RAM
- Loki : 0.2 vCPU, 512MB RAM
- AlertManager : 0.1 vCPU, 128MB RAM
