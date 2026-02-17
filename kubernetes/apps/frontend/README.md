# Frontend Next.js 14

## Architecture

```
Client (Navigateur)              Frontend Next.js (2 replicas)
     │                                  │
     ├── GET /page ─────────────────►   │ SSR (Server-Side Rendering)
     │   ◄── HTML complet               │   → Appel Backend interne
     │                                  │
     ├── GET /_next/static/* ───────►   │ Assets statiques (JS/CSS)
     │                                  │
     ├── POST /api/auth/* ──────────►   │ NextAuth (login/logout/session)
     │                                  │
     └── Client-side fetch ─────────►   │ API calls via NEXT_PUBLIC_API_URL
         (vers api.saas.local)          │
                                   ┌────┴────┐
                                   │ Backend │→ REST API (SSR calls)
                                   │ GraphQL │→ Queries SSR
                                   │ NextAuth│→ JWT session
                                   └──────────┘
```

## Variables d'environnement

| Variable | Source | Description |
|----------|--------|-------------|
| NODE_ENV | ConfigMap | production |
| PORT | ConfigMap | 3001 |
| BACKEND_URL | ConfigMap | URL interne backend (SSR) |
| NEXT_PUBLIC_API_URL | ConfigMap | URL publique API (client) |
| NEXT_PUBLIC_GRAPHQL_URL | ConfigMap | URL publique GraphQL (client) |
| NEXTAUTH_URL | ConfigMap | URL publique app |
| NEXTAUTH_SECRET | Secret | Cle chiffrement sessions |

## Health Check

| Endpoint | Type | Description |
|----------|------|-------------|
| `/api/health` | Liveness + Readiness | Le serveur Next.js repond |
| `/api/metrics` | Prometheus | Metriques custom |

## Scaling

- **Min replicas:** 2 (PDB minAvailable: 1)
- **Max replicas:** 4
- **Scale up:** CPU > 70% ou Memory > 80%, stabilisation 30s
- **Scale down:** stabilisation 5min, max 1 pod/2min

## Troubleshooting

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| Page blanche | `kubectl logs -l app=frontend -n production` | Verifier build Next.js, variables NEXT_PUBLIC_* |
| SSR timeout | Verifier connexion backend interne | Verifier BACKEND_URL, backend service up |
| Auth echoue | `kubectl logs -l app=frontend -n production \| grep auth` | Verifier NEXTAUTH_SECRET, backend auth endpoint |
| Assets 404 | Verifier Traefik Ingress routes | Verifier path rewriting, CDN config |
| High TTFB | Grafana dashboard Frontend | Optimiser SSR, activer ISR cache |
