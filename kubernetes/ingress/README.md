# Ingress Stack - Traefik + cert-manager + WAF

## Architecture

```
Internet
    │
    ▼
┌──────────────────────────────────────────────────┐
│            Hetzner Load Balancer                  │
│         (TCP passthrough 80/443)                  │
└───────────────┬──────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────┐
│  Traefik v3.0 (2 replicas - Node1 + Node2)       │
│                                                   │
│  ┌─────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ :80 web │→ │ redirect │→ │ :443 websecure   │ │
│  │  HTTP   │  │  HTTPS   │  │  TLS 1.3 only    │ │
│  └─────────┘  └──────────┘  └────────┬─────────┘ │
│                                       │           │
│  Middlewares Pipeline :               ▼           │
│  ┌──────────────────────────────────────────────┐ │
│  │ 1. Security Headers (HSTS, CSP, X-Frame...) │ │
│  │ 2. Rate Limiting (100/s frontend, 50/s API) │ │
│  │ 3. WAF ModSecurity (OWASP CRS 4.0, PL2)    │ │
│  │ 4. Compression (gzip/brotli)                │ │
│  └──────────────────────────────────────────────┘ │
└───────────────┬──────────────────────────────────┘
                │
    ┌───────────┼───────────┐
    ▼           ▼           ▼
┌────────┐ ┌────────┐ ┌──────────┐
│Frontend│ │Backend │ │ Grafana  │
│ :3001  │ │ :3000  │ │  :3000   │
│ app.   │ │ api.   │ │monitoring│
└────────┘ └────────┘ └──────────┘
```

## Flux TLS (cert-manager → Let's Encrypt → Traefik)

```
1. Certificate resource creee dans K8s
        │
        ▼
2. cert-manager detecte la ressource
        │
        ▼
3. cert-manager cree un Order ACME
        │
        ▼
4. cert-manager cree un pod HTTP-01 solver
   (repond sur /.well-known/acme-challenge/)
        │
        ▼
5. Let's Encrypt verifie le challenge HTTP-01
        │
        ▼
6. Let's Encrypt emet le certificat
        │
        ▼
7. cert-manager stocke le cert dans un Secret K8s
        │
        ▼
8. Traefik detecte le Secret et charge le cert
        │
        ▼
9. Traefik sert le TLS avec le nouveau certificat
```

## Domaines et Certificats

| Domaine | Service | Secret TLS | Middlewares |
|---------|---------|------------|-------------|
| app.saas.local | Frontend :3001 | frontend-tls | security-headers, compress, rate-limit-default |
| api.saas.local | Backend :3000 | backend-tls | security-headers, rate-limit-api, waf-modsecurity |
| api.saas.local/api/auth | Backend :3000 | backend-tls | security-headers, rate-limit-auth (10/min), waf |
| traefik.saas.local | Dashboard :8080 | traefik-tls | security-headers, basicauth |
| monitoring.saas.local | Grafana :3000 | monitoring-tls | security-headers, compress, ip-whitelist (opt) |

## Middlewares disponibles

| Middleware | Namespace | Description | Applique sur |
|-----------|-----------|-------------|-------------|
| security-headers | ingress | Headers OWASP (HSTS, CSP, X-Frame) | Global (entryPoint websecure) |
| redirect-https | ingress | HTTP → HTTPS permanent (301) | EntryPoint web |
| rate-limit-default | ingress | 100 req/s, burst 200 | Frontend |
| rate-limit-api | ingress | 50 req/s, burst 100 | Backend API |
| rate-limit-auth | ingress | 10 req/min, burst 20 | Auth endpoints |
| compress | ingress | gzip/brotli (>1KB) | Frontend, Grafana |
| waf-modsecurity | ingress | OWASP CRS 4.0, PL2, block mode | Backend API |
| ip-whitelist-admin | ingress | Restriction IP admin | Dashboard, Grafana (opt) |
| dashboard-auth | ingress | BasicAuth dashboard | Traefik dashboard |

## Deploiement

```bash
# 1. Installer les CRDs cert-manager (AVANT le deploiement)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml

# 2. Installer les CRDs Traefik
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/traefik.io_ingressroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/traefik.io_middlewares.yaml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/traefik.io_tlsoptions.yaml

# 3. Deployer la stack ingress
kubectl apply -k kubernetes/ingress/

# 4. Verifier cert-manager
kubectl get pods -n cert-manager
kubectl get clusterissuer

# 5. Verifier Traefik
kubectl get pods -n ingress
kubectl get svc -n ingress

# 6. Verifier les certificats
kubectl get certificates --all-namespaces
kubectl get certificaterequests --all-namespaces

# 7. Tester le TLS
openssl s_client -connect app.saas.local:443 -servername app.saas.local 2>/dev/null | openssl x509 -noout -dates -subject
```

## Ajout d'un nouveau domaine

```bash
# 1. Creer le Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nouveau-tls
  namespace: production
spec:
  secretName: nouveau-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - nouveau.saas.local
  renewBefore: 720h
  privateKey:
    algorithm: ECDSA
    size: 256
EOF

# 2. Creer l'IngressRoute
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nouveau-service
  namespace: production
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`nouveau.saas.local\`)
      kind: Rule
      middlewares:
        - name: security-headers
          namespace: ingress
      services:
        - name: nouveau-service
          port: 8080
  tls:
    secretName: nouveau-tls
EOF

# 3. Verifier
kubectl get certificate nouveau-tls -n production
kubectl describe certificate nouveau-tls -n production
```

## Configuration TLS

```
TLS 1.3 UNIQUEMENT
├── Cipher Suites (negociees automatiquement) :
│   ├── TLS_AES_256_GCM_SHA384
│   ├── TLS_CHACHA20_POLY1305_SHA256
│   └── TLS_AES_128_GCM_SHA256
├── SNI Strict : true (refuse connexions sans SNI)
├── HSTS : max-age=31536000; includeSubDomains; preload
├── Certificats : ECDSA P-256 (Let's Encrypt)
└── Renouvellement : automatique 30j avant expiration
```

## Troubleshooting

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| Certificat pas emis | `kubectl describe certificate <name>` | Verifier ClusterIssuer, DNS, HTTP-01 solver |
| Challenge HTTP-01 echoue | `kubectl get challenges` | Verifier que port 80 est ouvert, DNS pointe vers LB |
| 502 Bad Gateway | `kubectl logs -l app=traefik -n ingress` | Backend service down, verifier pods production |
| Rate limit atteint (429) | Verifier headers X-RateLimit-* | Ajuster rate-limit dans middleware |
| WAF faux positif (403) | `kubectl logs -l app=modsecurity -n ingress` | Ajouter exclusion CRS pour le path |
| TLS handshake failed | `openssl s_client -connect host:443` | Client ne supporte pas TLS 1.3 |
| Dashboard inaccessible | Verifier BasicAuth secret | `htpasswd -nb admin 'password'` puis recreer secret |
| Cert renouvellement fail | `kubectl describe order <name>` | Verifier ACME account key, rate limits LE |
| Headers securite manquants | `curl -I https://app.saas.local` | Verifier middleware security-headers applique |

## Renouvellement automatique

```
cert-manager verifie les certificats toutes les ~8h.
Si un certificat expire dans < 30 jours (renewBefore: 720h) :
  1. Nouvelle CertificateRequest creee
  2. Nouveau challenge ACME
  3. Nouveau certificat stocke dans le Secret
  4. Traefik recharge automatiquement le Secret
  5. Zero downtime
```

## Metriques Prometheus

| Metrique | Description |
|---------|-------------|
| traefik_entrypoint_requests_total | Total requetes par entryPoint |
| traefik_service_requests_total | Total requetes par service |
| traefik_service_request_duration_seconds | Latence par service |
| traefik_tls_certs_not_after | Expiration certificats TLS |
| traefik_entrypoint_open_connections | Connexions ouvertes |
