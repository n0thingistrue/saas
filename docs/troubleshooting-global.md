# Troubleshooting Global - Index consolide

## Index des problemes par composant

Ce document centralise tous les problemes connus et leurs solutions.
Pour les details, consulter les runbooks specifiques.

---

## 1. Cluster K3s

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| Node NotReady | `kubectl get nodes` → NotReady | Verifier `systemctl status k3s` / `k3s-agent` | [common-issues](troubleshooting/common-issues.md) |
| Nodes ne se voient pas | 1 seul node visible | Verifier firewall port 6443, token K3s, WireGuard | [common-issues](troubleshooting/common-issues.md) |
| Pods Pending | Pods bloqués en Pending | `kubectl describe pod` → verifier resources, affinity, PVC | [common-issues](troubleshooting/common-issues.md) |
| Pods CrashLoopBackOff | Restart constant | `kubectl logs --previous` → ConfigMap, DB, port | [common-issues](troubleshooting/common-issues.md) |
| CoreDNS down | Resolution DNS echoue | Restart CoreDNS : `kubectl rollout restart -n kube-system deployment/coredns` | - |
| etcd high latency | Cluster lent | Verifier I/O disque, compacter etcd | - |
| Certificate expired | API server inaccessible | `k3s certificate rotate` puis restart | - |

### Commandes de diagnostic K3s

```bash
# Etat global
kubectl get nodes -o wide
kubectl get pods --all-namespaces | grep -v Running
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Ressources
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=cpu | head -10

# Logs systeme
journalctl -u k3s --no-pager -n 50        # Node 1
journalctl -u k3s-agent --no-pager -n 50   # Node 2
```

---

## 2. PostgreSQL (Patroni)

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| Connection refused | Backend ne peut pas se connecter | Verifier pod, service, endpoints | [postgresql.md](runbooks/postgresql.md) |
| Replication lag | Lag > 10s | Verifier reseau, charge I/O | [postgresql.md](runbooks/postgresql.md) |
| Failover ne se declenche pas | Primary down, pas de promotion | `patronictl failover --force` | [postgresql.md](runbooks/postgresql.md) |
| Split brain | 2 primaries detectes | `patronictl list`, forcer un standby | [postgresql.md](runbooks/postgresql.md) |
| Disk full | Erreurs d'ecriture | Nettoyer WAL, etendre PVC | [common-issues](troubleshooting/common-issues.md) |
| Slow queries | Latence elevee | Analyser `pg_stat_statements`, EXPLAIN | [postgresql.md](runbooks/postgresql.md) |
| Backup WAL-G echoue | Backup non cree | Verifier acces S3, credentials | [postgresql.md](runbooks/postgresql.md) |
| Corrupted data | Erreurs checksum | PITR depuis WAL-G | [postgresql.md](runbooks/postgresql.md) |

### Commandes de diagnostic PostgreSQL

```bash
# Etat Patroni
kubectl exec -n production postgresql-0 -- patronictl list

# Replication
kubectl exec -n production postgresql-0 -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Connexions
kubectl exec -n production postgresql-0 -- \
  psql -U postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Taille base
kubectl exec -n production postgresql-0 -- \
  psql -U postgres -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database ORDER BY pg_database_size(pg_database.datname) DESC;"

# Verifier les locks
kubectl exec -n production postgresql-0 -- \
  psql -U postgres -c "SELECT * FROM pg_locks WHERE NOT granted;"

# Backups WAL-G
kubectl exec -n production postgresql-0 -- wal-g backup-list
```

---

## 3. Redis (Sentinel)

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| Master down | Connection perdue | Sentinel failover auto (< 15s) | [redis.md](runbooks/redis.md) |
| Memory exceeded | OOM, evictions | Verifier maxmemory, analyser bigkeys | [common-issues](troubleshooting/common-issues.md) |
| Sentinel quorum perdu | Pas de failover | Verifier les 3 sentinels, reseau | [redis.md](runbooks/redis.md) |
| Replication desynchro | Replica desynchronise | `SLAVEOF NO ONE` puis re-sync | [redis.md](runbooks/redis.md) |
| Persistence echouee | RDB/AOF errors | Verifier disque, permissions | [redis.md](runbooks/redis.md) |
| Latence elevee | Slow commands | `redis-cli --latency`, `SLOWLOG` | [redis.md](runbooks/redis.md) |

### Commandes de diagnostic Redis

```bash
# Info master
kubectl exec -n production redis-0 -- redis-cli INFO replication

# Sentinel status
kubectl exec -n production redis-sentinel-0 -- \
  redis-cli -p 26379 SENTINEL master mymaster

# Memoire
kubectl exec -n production redis-0 -- redis-cli INFO memory

# Slow log
kubectl exec -n production redis-0 -- redis-cli SLOWLOG GET 10

# Big keys
kubectl exec -n production redis-0 -- redis-cli --bigkeys
```

---

## 4. Traefik (Ingress)

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| 502 Bad Gateway | Service backend down | Verifier pod/service/endpoints backend | [traefik.md](runbooks/traefik.md) |
| 503 Service Unavailable | Pas de backend disponible | Verifier IngressRoute, service selectors | [traefik.md](runbooks/traefik.md) |
| Certificat invalide | Erreur TLS navigateur | Verifier cert-manager, certificates | [traefik.md](runbooks/traefik.md) |
| WAF bloque requete | 403 Forbidden | Verifier ModSecurity logs, ajuster rules | [traefik.md](runbooks/traefik.md) |
| Rate limit atteint | 429 Too Many Requests | Verifier config rate limit, whitelist | [traefik.md](runbooks/traefik.md) |
| Redirect loop | ERR_TOO_MANY_REDIRECTS | Verifier middleware redirect-https | [traefik.md](runbooks/traefik.md) |
| ProxyProtocol erreur | IP source incorrecte | Verifier config LB Hetzner, trusted IPs | [traefik.md](runbooks/traefik.md) |

### Commandes de diagnostic Traefik

```bash
# Etat pods
kubectl get pods -n ingress -l app=traefik -o wide

# Logs
kubectl logs -n ingress -l app=traefik --tail=50

# IngressRoutes
kubectl get ingressroute --all-namespaces

# Certificats
kubectl get certificates --all-namespaces

# Dashboard (port-forward)
kubectl port-forward -n ingress svc/traefik-internal 8080:8080
# Acceder http://localhost:8080/dashboard/
```

---

## 5. Applications (Backend / Frontend)

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| Backend OOM | Pod killed (OOMKilled) | Augmenter memory limits, analyser les fuites | - |
| Frontend SSR lent | p95 > 1s | Verifier cache Redis, optimiser pages | - |
| LDAP auth echoue | 401 Unauthorized | Verifier Samba-AD, LDAP bind credentials | - |
| Database connection pool | Too many connections | Verifier pool size, max connections PG | - |
| Image pull failed | ErrImagePull | Verifier imagePullSecrets, registry | - |
| HPA ne scale pas | Replicas stagnent | Verifier metrics-server, resource requests | - |

### Commandes de diagnostic Applications

```bash
# Logs backend
kubectl logs -n production -l app=backend --tail=50 -f

# Logs frontend
kubectl logs -n production -l app=frontend --tail=50 -f

# Restart history
kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# HPA status
kubectl get hpa -n production
kubectl describe hpa backend-hpa -n production

# Health checks
kubectl exec -n production deploy/backend -- curl -s localhost:3000/health
kubectl exec -n production deploy/frontend -- curl -s localhost:3001/
```

---

## 6. Monitoring (Prometheus / Grafana / Loki)

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| Prometheus disk full | Ingestion arretee | Reduire retention, compacter TSDB | - |
| Target down | Metriques manquantes | Verifier ServiceMonitor, labels | [common-issues](troubleshooting/common-issues.md) |
| Grafana inaccessible | 504 Gateway Timeout | Verifier pod, port-forward secours | [common-issues](troubleshooting/common-issues.md) |
| Alertes non recues | Slack silencieux | Verifier webhook URL, silences AM | - |
| Loki OOM | Pod crash | Augmenter memoire, reduire ingestion rate | - |
| Promtail pas de logs | Logs absents dans Loki | Verifier DaemonSet, mount paths | - |

### Commandes de diagnostic Monitoring

```bash
# Prometheus
kubectl get pods -n monitoring -l app=prometheus
kubectl exec -n monitoring prometheus-0 -- df -h /prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Grafana
kubectl get pods -n monitoring -l app=grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Loki
kubectl get pods -n monitoring -l app=loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# AlertManager
kubectl get pods -n monitoring -l app=alertmanager
kubectl port-forward -n monitoring svc/alertmanager 9093:9093

# Promtail
kubectl get pods -n monitoring -l app=promtail
kubectl logs -n monitoring -l app=promtail --tail=20
```

---

## 7. ArgoCD (GitOps)

| Probleme | Symptome | Solution rapide | Runbook |
|----------|----------|-----------------|---------|
| App OutOfSync | Diff entre Git et cluster | `argocd app sync <app>` | [gitops.md](gitops.md) |
| App Degraded | Pod not healthy | Check pod logs, events | [gitops.md](gitops.md) |
| Sync Failed | Erreur de manifest | `argocd app get <app>` → Events | [gitops.md](gitops.md) |
| Drift detected | Modification manuelle | Self-heal auto, ou `argocd app sync` | [gitops.md](gitops.md) |
| Image not found | Registry erreur | Verifier imagePullSecrets, tag | - |
| Stuck Progressing | Timeout deploiement | Check resources, PDB, node capacity | - |

### Commandes de diagnostic ArgoCD

```bash
# Applications
argocd app list
argocd app get <app-name>
argocd app diff <app-name>

# Sync force
argocd app sync <app-name> --force

# Rollback
argocd app rollback <app-name>

# Logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

---

## 8. Securite

| Probleme | Symptome | Solution rapide | Detail |
|----------|----------|-----------------|--------|
| WAF false positive | 403 sur requete legitime | Ajouter exclusion ModSecurity | Voir modsecurity.conf |
| Rate limit client | 429 pour utilisateur normal | Ajuster seuils ou whitelist IP | middleware-rate-limit.yaml |
| SealedSecret expiré | Secret non dechiffre | Re-sealer avec nouvelle cle publique | sealed-secrets/ |
| Brute force detecte | Alertes rate-limit-auth | Verifier logs, bloquer IP source | Hetzner firewall |
| CVE critique | Scan Trivy alert | Mettre a jour l'image, rebuild | CI/CD |

---

## Arbre de decision

```
Probleme detecte
    |
    +-- Service inaccessible ?
    |   |
    |   +-- Traefik down ? → Verifier pods ingress
    |   +-- Backend down ? → Verifier pods production + DB
    |   +-- DNS ? → Verifier CoreDNS, resolution
    |   +-- Certificat ? → Verifier cert-manager
    |
    +-- Performance degradee ?
    |   |
    |   +-- CPU/Memory ? → kubectl top, HPA
    |   +-- Latence DB ? → pg_stat_statements, slow queries
    |   +-- Latence Redis ? → SLOWLOG, memory
    |   +-- Network ? → WireGuard, NetworkPolicies
    |
    +-- Donnees ?
    |   |
    |   +-- Perte de donnees ? → WAL-G restore, PITR
    |   +-- Corruption ? → pg_checksums, restore
    |   +-- Replication cassee ? → Patroni reinit, Redis SLAVEOF
    |
    +-- Securite ?
        |
        +-- Attaque DDoS ? → Rate limit + WAF + Hetzner FW
        +-- Intrusion ? → Logs, NetworkPolicies, isoler
        +-- CVE ? → Patch, rebuild, deploy
```

---

## Contacts et escalade

| Niveau | Contact | Delai |
|--------|---------|-------|
| L1 - Monitoring | AlertManager → Slack | Automatique (< 2min) |
| L2 - Admin | Administrateur infrastructure | < 15min (P1), < 2h (P2) |
| L3 - Fournisseur | Hetzner Support (support@hetzner.com) | 24/7 pour hardware |

## References

- [Architecture detaillee](architecture/architecture.md)
- [Procedures d'exploitation](procedures-exploitation.md)
- [Gestion des incidents](procedures/incident-management.md)
- [Runbook PostgreSQL](runbooks/postgresql.md)
- [Runbook Redis](runbooks/redis.md)
- [Runbook Traefik](runbooks/traefik.md)
- [CI/CD](cicd.md)
- [GitOps](gitops.md)
