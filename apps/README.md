# Applications

## Vue d'ensemble

Dockerfiles et configurations pour les applications déployées dans le cluster.
Le code source applicatif est dans des repositories séparés - ici on ne gère que
les artefacts de containerisation.

## Structure

```
apps/
├── frontend/
│   ├── Dockerfile              # Multi-stage build Next.js
│   ├── .dockerignore
│   └── next.config.js          # Configuration SSR production
└── backend/
    ├── Dockerfile              # Multi-stage build NestJS
    ├── .dockerignore
    └── nest-cli.json           # Configuration build production
```

## Build

```bash
# Frontend
docker build -t saas-frontend:latest apps/frontend/

# Backend
docker build -t saas-backend:latest apps/backend/
```

## Images

Les images sont buildées par GitHub Actions et pushées vers le registry.
ArgoCD détecte les nouvelles images et synchronise les déploiements.
