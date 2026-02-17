# Troubleshooting - Problèmes courants

## Cluster K3s

### Les nodes ne se voient pas

**Symptôme** : `kubectl get nodes` montre un seul node ou node `NotReady`

**Diagnostic** :
```bash
# Sur Node 2, vérifier le service K3s agent
systemctl status k3s-agent

# Vérifier la connectivité réseau
ping -c 3 <node1-private-ip>

# Vérifier WireGuard
wg show
```

**Solutions** :
1. Vérifier le firewall Hetzner (port 6443 TCP ouvert)
2. Vérifier le token K3s : `/var/lib/rancher/k3s/server/node-token`
3. Redémarrer l'agent : `systemctl restart k3s-agent`

### Pods en Pending

**Symptôme** : Pods restent en `Pending`

**Diagnostic** :
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Causes fréquentes** :
- **Insufficient resources** : Réduire les requests ou ajouter des resources
- **No matching node** : Vérifier les nodeAffinity/tolerations
- **PVC pending** : Vérifier le StorageClass et les volumes disponibles

### Pods en CrashLoopBackOff

**Diagnostic** :
```bash
kubectl logs <pod-name> -n <namespace> --previous
kubectl describe pod <pod-name> -n <namespace>
```

**Causes fréquentes** :
- Erreur de configuration (ConfigMap/Secret)
- Base de données non accessible
- Port déjà utilisé
- Healthcheck trop strict

## Réseau

### Services inaccessibles depuis l'extérieur

```bash
# Vérifier Traefik
kubectl get pods -n ingress
kubectl logs -n ingress -l app=traefik

# Vérifier IngressRoute
kubectl get ingressroute -n production

# Vérifier le Load Balancer Hetzner
hcloud load-balancer describe <lb-id>

# Vérifier la Floating IP
hcloud floating-ip describe <fip-id>
```

### DNS ne résout pas

```bash
# Vérifier la résolution depuis un pod
kubectl run -it --rm debug --image=busybox -- nslookup backend.production.svc.cluster.local

# Vérifier CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

## PostgreSQL

### Connection refused

```bash
# Vérifier le pod
kubectl get pods -n production -l app=postgresql

# Vérifier le service
kubectl get svc -n production postgresql
kubectl get endpoints -n production postgresql

# Tester la connexion depuis un pod
kubectl run -it --rm debug --image=postgres:16 -- psql -h postgresql.production.svc -U postgres
```

### Disk full

```bash
# Vérifier l'espace
kubectl exec -n production postgresql-0 -- df -h /var/lib/postgresql/data

# Nettoyer les WAL anciens
kubectl exec -n production postgresql-0 -- wal-g delete --confirm retain FULL 5

# Étendre le PVC (si StorageClass supporte l'expansion)
kubectl patch pvc data-postgresql-0 -n production -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

## Redis

### Memory exceeded

```bash
# Vérifier la mémoire
kubectl exec -n production redis-0 -- redis-cli info memory

# Vérifier la politique d'éviction
kubectl exec -n production redis-0 -- redis-cli config get maxmemory-policy

# Analyser les clés
kubectl exec -n production redis-0 -- redis-cli --bigkeys
```

## Certificats TLS

### Certificat expiré ou non émis

```bash
# Vérifier les certificats
kubectl get certificates -n ingress
kubectl describe certificate <name> -n ingress

# Vérifier cert-manager
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager

# Forcer le renouvellement
kubectl delete certificate <name> -n ingress
```

## Monitoring

### Prometheus ne scrape pas les métriques

```bash
# Vérifier les targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Accéder http://localhost:9090/targets

# Vérifier les ServiceMonitors
kubectl get servicemonitor -n monitoring

# Vérifier les labels de matching
kubectl get servicemonitor <name> -n monitoring -o yaml | grep -A5 selector
```

### Grafana inaccessible

```bash
# Vérifier le pod
kubectl get pods -n monitoring -l app=grafana

# Récupérer le mot de passe admin
kubectl get secret -n monitoring grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Port-forward de secours
kubectl port-forward -n monitoring svc/grafana 3000:3000
```
