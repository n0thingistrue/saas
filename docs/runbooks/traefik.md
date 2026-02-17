# Runbook Traefik + WAF

## Informations service

| Champ | Valeur |
|-------|--------|
| Namespace | `ingress` |
| Deployment | `traefik` |
| Ports | 80 (HTTP→redirect), 443 (HTTPS), 8080 (dashboard) |
| WAF | ModSecurity Core Rule Set (CRS) |
| TLS | Let's Encrypt via cert-manager |

## Commandes courantes

```bash
# Vérifier l'état
kubectl get pods -n ingress
kubectl get ingressroute --all-namespaces

# Logs Traefik
kubectl logs -n ingress -l app=traefik -f

# Dashboard (port-forward)
kubectl port-forward -n ingress svc/traefik-dashboard 9000:9000
# Accéder à http://localhost:9000/dashboard/
```

## Certificats TLS

```bash
# Lister les certificats
kubectl get certificates -n ingress
kubectl get certificaterequest -n ingress

# Renouveler manuellement
kubectl delete certificate <name> -n ingress
# cert-manager recréera automatiquement
```

## Alertes

| Alerte | Seuil | Action |
|--------|-------|--------|
| TraefikDown | Pod indisponible | Vérifier deployment, reschedule |
| CertExpiringSoon | < 14 jours | Vérifier cert-manager logs |
| HighErrorRate | 5xx > 5% | Vérifier backends, logs |
| WAFBlocking | > 100 blocks/min | Analyser false positives |

## Troubleshooting

### Certificat non émis

```bash
kubectl describe certificate <name> -n ingress
kubectl describe certificaterequest <name> -n ingress
kubectl logs -n cert-manager -l app=cert-manager
```

### 502 Bad Gateway

```bash
# Vérifier que le backend répond
kubectl get endpoints -n production
kubectl exec -n ingress <traefik-pod> -- wget -qO- http://backend.production.svc:3000/health
```
