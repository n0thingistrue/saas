# Architecture détaillée

## Diagramme d'architecture globale

```mermaid
graph TB
    subgraph Internet
        User[Utilisateurs]
        DNS[DNS - CloudFlare]
    end

    subgraph Hetzner Cloud
        FIP[Floating IP<br/>78.x.x.x]
        LB[Load Balancer<br/>Hetzner]

        subgraph VPN[WireGuard VPN - 10.0.0.0/24]
            subgraph Node1[Node 1 - 16vCPU/32GB - CCX33]
                K3S_S[K3s Server<br/>Control Plane]
                PG_P[(PostgreSQL<br/>Primary)]
                REDIS_M[(Redis<br/>Master)]
                BE1[Backend<br/>NestJS x2]
                FE1[Frontend<br/>Next.js x1]
                SAMBA[Samba-AD<br/>Primary]
                MON[Prometheus<br/>Grafana<br/>Loki]
                TRAEFIK[Traefik<br/>+ WAF]
            end

            subgraph Node2[Node 2 - 4vCPU/16GB - CCX23]
                K3S_A[K3s Agent<br/>Worker]
                PG_S[(PostgreSQL<br/>Standby)]
                REDIS_R[(Redis<br/>Replica)]
                BE2[Backend<br/>NestJS x1]
                FE2[Frontend<br/>Next.js x1]
                WAZUH[Wazuh<br/>Agent]
                STAGING[Staging<br/>on-demand]
            end
        end

        S3[(Hetzner S3<br/>Backups)]
    end

    subgraph External
        B2[(Backblaze B2<br/>Backup offsite)]
        GH[GitHub<br/>Repository]
    end

    User --> DNS --> FIP --> LB
    LB --> TRAEFIK
    TRAEFIK --> FE1 & FE2
    FE1 & FE2 --> BE1 & BE2
    BE1 & BE2 --> PG_P & REDIS_M
    BE1 & BE2 --> SAMBA

    PG_P -- Streaming<br/>Replication --> PG_S
    REDIS_M -- Replication --> REDIS_R

    PG_P -- WAL-G --> S3
    S3 -- Offsite --> B2

    GH -- GitOps --> K3S_S
    MON -. Monitoring .-> Node2
    WAZUH -. Security .-> Node1
```

## Diagramme réseau

```mermaid
graph LR
    subgraph Public Network
        FIP[Floating IP]
        LB[Load Balancer]
        N1_PUB[Node1 Public IP]
        N2_PUB[Node2 Public IP]
    end

    subgraph Private Network - 10.10.0.0/16
        N1_PRIV[Node1<br/>10.10.0.2]
        N2_PRIV[Node2<br/>10.10.0.3]
    end

    subgraph WireGuard Tunnel - 10.0.0.0/24
        WG1[wg0: 10.0.0.1]
        WG2[wg0: 10.0.0.2]
    end

    subgraph K3s Pod Network - 10.42.0.0/16
        PODS1[Node1 Pods]
        PODS2[Node2 Pods]
    end

    subgraph K3s Service Network - 10.43.0.0/16
        SVC[ClusterIP Services]
    end

    FIP --> LB --> N1_PUB & N2_PUB
    N1_PRIV <--> N2_PRIV
    WG1 <--> WG2
    PODS1 <--> SVC <--> PODS2
```

## Diagramme de flux de données

```mermaid
sequenceDiagram
    participant U as Utilisateur
    participant T as Traefik + WAF
    participant F as Frontend (Next.js)
    participant B as Backend (NestJS)
    participant S as Samba-AD
    participant P as PostgreSQL
    participant R as Redis
    participant L as Loki

    U->>T: HTTPS Request
    T->>T: WAF ModSecurity check
    T->>F: Route vers Frontend
    F->>B: API Request (REST/GraphQL)
    B->>R: Check cache
    alt Cache hit
        R-->>B: Cached data
    else Cache miss
        B->>P: Query SQL
        P-->>B: Result
        B->>R: Store in cache
    end
    B->>S: Verify auth (LDAP/Kerberos)
    S-->>B: Auth token
    B-->>F: JSON response
    F-->>T: HTML/JSON
    T-->>U: HTTPS Response

    Note over T,L: Tous les composants envoient leurs logs à Loki via Promtail
```

## Choix d'architecture

### Pourquoi K3s et non K8s vanilla ?

- **Empreinte mémoire réduite** : ~512MB vs ~2GB pour le control plane
- **Binaire unique** : Installation simplifiée
- **SQLite/etcd intégré** : Pas besoin d'etcd externe
- **Traefik intégré** : Ingress controller inclus
- **Certifié CNCF** : Conformité Kubernetes garantie
- **Adapté pour 2 nodes** : Conçu pour les petits clusters

### Pourquoi Patroni pour PostgreSQL ?

- **Failover automatique** : Promotion standby en < 30s
- **DCS intégré** : Consensus distribué sans dépendance externe (utilise K8s endpoints)
- **Streaming replication** : RPO proche de 0 en mode synchrone
- **Compatible WAL-G** : Backup continu intégré

### Pourquoi Redis Sentinel et non Cluster ?

- **2 nodes seulement** : Redis Cluster nécessite minimum 6 nodes
- **Sentinel** : Supervision + failover automatique avec 2 instances
- **Simplicité** : Configuration simple, adapté à la taille du projet

### Pourquoi Samba-AD ?

- **Solution open-source** : Active Directory compatible sans licence
- **LDAP + Kerberos + SSO** : Triple protocole d'authentification
- **Intégration NestJS** : passport-ldapauth + passport-kerberos
- **RNCP** : Démontre compétences AD dans contexte entreprise
