# Sécurité

## Vue d'ensemble

Implémentation Defense in Depth avec plusieurs couches de sécurité :

1. **Réseau** : WireGuard VPN inter-nodes, NetworkPolicies, firewall Hetzner
2. **Ingress** : WAF ModSecurity, TLS Let's Encrypt, rate limiting
3. **Cluster** : RBAC, Pod Security Standards, Sealed Secrets
4. **Host** : fail2ban, durcissement SSH, audit logs
5. **Monitoring** : Wazuh SIEM, alertes sécurité Prometheus

## Structure

```
security/
├── fail2ban/                   # Protection brute-force SSH/services
│   ├── jail.local              # Configuration jails
│   └── filter.d/               # Filtres personnalisés
├── wireguard/                  # VPN inter-nodes
│   ├── setup-wireguard.sh      # Script installation
│   └── wg0.conf.example        # Template configuration
├── sealed-secrets/             # Gestion secrets chiffrés
│   ├── controller.yaml         # SealedSecrets controller
│   └── README.md               # Guide utilisation
└── policies/                   # Policies de sécurité
    ├── pod-security.yaml       # Pod Security Standards
    ├── network-policies.yaml   # Isolation réseau
    └── rbac-audit.yaml         # Audit RBAC
```

## WireGuard VPN

Tunnel chiffré entre Node 1 et Node 2 pour le trafic interne :
- Interface : `wg0`
- Réseau : `10.0.0.0/24`
- Port : `51820/UDP`
- Chiffrement : ChaCha20-Poly1305

## fail2ban

Protections activées :
- SSH : 3 tentatives → ban 1h
- Traefik : détection brute-force HTTP 401/403
- K3s API : protection endpoint API

## Sealed Secrets

Tous les secrets Kubernetes sont chiffrés avec kubeseal avant commit :
```bash
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```
Seul le controller dans le cluster peut déchiffrer.
