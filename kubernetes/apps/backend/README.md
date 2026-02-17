# Backend NestJS API

## Architecture

```
Traefik Ingress                  Backend NestJS (3 replicas)
     │                                  │
     ├── /api/* ────────────────────►   │ REST API (CRUD, auth, business)
     │                                  │
     ├── /graphql ──────────────────►   │ GraphQL (queries, mutations, subs)
     │                                  │
     └── /metrics ──────────────────►   │ Prometheus metrics
                                        │
                                   ┌────┴────┐
                                   │ PG      │→ TypeORM/Prisma (ORM)
                                   │ Redis   │→ Sessions + Cache
                                   │ LDAP    │→ Auth passport-ldapauth
                                   │ JWT     │→ Access + Refresh tokens
                                   └──────────┘
```

## Flux d'authentification

```
1. Client → POST /api/auth/login (username, password)
2. Backend → LDAP Bind (samba-ad:389) avec credentials
3. Samba-AD → Verifie password, retourne user attributes
4. Backend → Genere JWT access token (1h) + refresh token (7j)
5. Client → Authorization: Bearer <access_token>
6. Backend → Valide JWT, extrait roles depuis LDAP groups
```

## Variables d'environnement

| Variable | Source | Description |
|----------|--------|-------------|
| NODE_ENV | ConfigMap | production |
| API_PORT | ConfigMap | 3000 |
| DATABASE_HOST | ConfigMap | postgresql-primary.production.svc |
| DATABASE_PASSWORD | Secret | Mot de passe PostgreSQL |
| REDIS_HOST | ConfigMap | redis-master.production.svc |
| REDIS_PASSWORD | Secret | Mot de passe Redis |
| LDAP_URL | ConfigMap | ldap://samba-ad:389 |
| LDAP_BIND_PASSWORD | Secret | Mot de passe LDAP bind |
| JWT_SECRET | Secret | Cle signature access tokens |
| JWT_REFRESH_SECRET | Secret | Cle signature refresh tokens |

## Health Checks

| Endpoint | Type | Description |
|----------|------|-------------|
| `/health` | Liveness | Le process NestJS tourne |
| `/health/ready` | Readiness | DB + Redis connectes |
| `/metrics` | Prometheus | Metriques applicatives |

## Scaling

- **Min replicas:** 3 (PDB minAvailable: 2)
- **Max replicas:** 6
- **Scale up:** CPU > 70% ou Memory > 80%, stabilisation 30s
- **Scale down:** stabilisation 5min, max 1 pod/2min

## Troubleshooting

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| 502 Bad Gateway | `kubectl logs -l app=backend -n production` | Verifier readinessProbe, DB connexion |
| LDAP auth failed | `kubectl exec <pod> -- curl -s localhost:3000/health/ready` | Verifier LDAP_BIND_PASSWORD, Samba-AD up |
| High latency | Grafana dashboard Backend | Verifier slow queries PG, cache Redis |
| OOM Killed | `kubectl describe pod <pod> -n production` | Augmenter memory limits, profiler app |
| JWT invalid | Verifier logs NestJS | Verifier JWT_SECRET coherent entre pods |
