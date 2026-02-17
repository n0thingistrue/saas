# Procédure de gestion des incidents

## Classification des incidents

| Niveau | Description | Temps de réponse | Exemples |
|--------|-------------|------------------|----------|
| P1 - Critique | Service complètement indisponible | < 15 min | Cluster down, DB corrompue |
| P2 - Majeur | Fonctionnalité majeure dégradée | < 30 min | PostgreSQL failover, 1 node down |
| P3 - Mineur | Fonctionnalité mineure impactée | < 2h | Pod restart, cache miss élevé |
| P4 - Info | Anomalie sans impact utilisateur | < 24h | Warning logs, disk 70% |

## Processus de réponse

### 1. Détection

Sources de détection :
- AlertManager (alertes automatiques)
- Grafana (dashboards)
- Wazuh (alertes sécurité)
- Utilisateurs (remontées)

### 2. Triage

```bash
# État global rapide
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory | head -20
```

### 3. Diagnostic

Selon le symptôme, consulter le runbook correspondant :
- [PostgreSQL](../runbooks/postgresql.md)
- [Redis](../runbooks/redis.md)
- [Traefik](../runbooks/traefik.md)

### 4. Résolution

Appliquer la correction identifiée. Documenter chaque action.

### 5. Post-mortem

Pour tout incident P1/P2, rédiger un post-mortem :
- Timeline des événements
- Root cause analysis
- Actions correctives
- Améliorations préventives

## Scénarios courants

### Node 1 down (control plane)

```bash
# 1. Vérifier l'accès au cluster
kubectl get nodes

# 2. Si le control plane est down, attendre le redémarrage auto Hetzner
#    ou redémarrer manuellement via Hetzner Console/API
hcloud server reboot node-1

# 3. Vérifier le recovery
kubectl get nodes
kubectl get pods --all-namespaces
```

### Node 2 down (worker)

```bash
# 1. Impact : replicas HA perdus (standby PG, replica Redis, 1 backend)
# 2. Le trafic est automatiquement redirigé vers Node 1
# 3. Redémarrer Node 2
hcloud server reboot node-2

# 4. Vérifier que les pods sont reschedulés
kubectl get pods --all-namespaces -o wide
```

### PostgreSQL primary down

```bash
# Patroni gère le failover automatiquement
# 1. Vérifier le failover
kubectl exec -n production postgresql-0 -- patronictl list

# 2. Si pas de failover auto, forcer
kubectl exec -n production postgresql-0 -- patronictl failover --force
```

### Attaque DDoS détectée

```bash
# 1. Vérifier les logs WAF
kubectl logs -n ingress -l app=traefik | grep -i "ModSecurity"

# 2. Activer rate limiting strict
kubectl apply -f kubernetes/ingress/waf/emergency-ratelimit.yaml

# 3. Bloquer les IPs suspectes via Hetzner firewall
hcloud firewall add-rule <firewall-id> --direction in --source-ips <ip>/32 --protocol tcp --port 443 --action drop
```

## Contacts escalade

| Rôle | Contact | Disponibilité |
|------|---------|--------------|
| Admin Infra | [votre-email] | 24/7 pour P1 |
| Responsable Sécurité | [email] | Heures ouvrées |
| Hetzner Support | support@hetzner.com | 24/7 |
