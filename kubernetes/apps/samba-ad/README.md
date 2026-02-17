# Samba Active Directory

## Architecture

```
Backend NestJS                     Samba-AD (Node 1)
     │                                  │
     ├── LDAP Bind (389) ──────────────►│ Annuaire Users/Groups
     │   CN=app-backend,OU=Services     │
     │                                  │
     ├── LDAP Search ──────────────────►│ Recherche utilisateur
     │   OU=Users,DC=saas,DC=local      │
     │                                  │
     ├── Kerberos (88) ────────────────►│ Ticket TGT (SSO)
     │   SAAS.LOCAL realm               │
     │                                  │
     └── LDAPS (636) ─────────────────►│ LDAP chiffre TLS
                                        │
                                   ┌────┴────┐
                                   │ sam.ldb  │  Base AD
                                   │ DNS zone │  saas.local
                                   │ Kerberos │  KDC
                                   │ SYSVOL   │  GPO
                                   └──────────┘
```

## Integration Backend NestJS

```typescript
// Configuration LDAP dans NestJS (passport-ldapauth)
{
  server: {
    url: 'ldap://samba-ad.production.svc.cluster.local:389',
    bindDN: 'CN=app-backend,OU=Services,DC=saas,DC=local',
    bindCredentials: process.env.LDAP_BIND_PASSWORD,
    searchBase: 'OU=Users,DC=saas,DC=local',
    searchFilter: '(&(objectClass=user)(sAMAccountName={{username}}))',
    searchAttributes: ['dn', 'sAMAccountName', 'mail', 'displayName', 'memberOf'],
  }
}
```

## Gestion utilisateurs

```bash
# Lister les utilisateurs
kubectl exec -n production samba-ad-0 -- samba-tool user list

# Creer un utilisateur
kubectl exec -n production samba-ad-0 -- samba-tool user create jdupont 'MotDePasse!' \
  --userou="OU=Users" --given-name="Jean" --surname="Dupont" --mail-address="jdupont@saas.local"

# Ajouter a un groupe
kubectl exec -n production samba-ad-0 -- samba-tool group addmembers developers jdupont

# Desactiver un compte
kubectl exec -n production samba-ad-0 -- samba-tool user disable jdupont

# Lister les groupes
kubectl exec -n production samba-ad-0 -- samba-tool group list

# Tester LDAP
kubectl exec -n production samba-ad-0 -- ldapsearch -x -H ldap://localhost:389 \
  -b "OU=Users,DC=saas,DC=local" -D "CN=Administrator,CN=Users,DC=saas,DC=local" \
  -w "$ADMIN_PASSWORD" "(objectClass=user)" sAMAccountName mail
```

## Troubleshooting

| Probleme | Diagnostic | Solution |
|----------|-----------|----------|
| LDAP bind failed | `ldapsearch -x -H ldap://localhost:389 -D "..." -w "..."` | Verifier credentials, bind DN |
| DNS ne resout pas | `host -t SRV _ldap._tcp.saas.local 127.0.0.1` | Verifier que samba tourne : `samba-tool drs showrepl` |
| Kerberos KDC down | `kinit admin@SAAS.LOCAL` | Restart pod, verifier `/var/lib/samba/private/` |
| Account locked | `samba-tool user show <user>` | `samba-tool user unlock <user>` |
