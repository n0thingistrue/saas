#!/usr/bin/env bash
# =============================================================================
# Vérifications post-installation K3s
# =============================================================================
# Vérifie que le cluster K3s est correctement configuré et prêt.
# À exécuter depuis Node 1 (control plane) après installation des 2 nodes.
#
# Vérifie :
#   - Nodes ready
#   - Pods système fonctionnels
#   - Réseau inter-nodes
#   - DNS du cluster
#   - Stockage
#   - Volumes Hetzner montés
#
# Usage:
#   ./03-post-install.sh
# =============================================================================
set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_check() { echo -e "  ${GREEN}[CHECK]${NC} $*"; }

ERRORS=0
WARNINGS=0

check_pass() { log_info "$1"; }
check_fail() { log_error "$1"; ((ERRORS++)); }
check_warn() { log_warn "$1"; ((WARNINGS++)); }

echo ""
echo "============================================"
echo "  Vérifications post-installation K3s"
echo "============================================"
echo ""

# --- 1. Nodes ----------------------------------------------------------------
echo "--- Nodes ---"

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [[ "$NODE_COUNT" -eq 2 ]]; then
    check_pass "2 nodes détectés"
else
    check_fail "Attendu: 2 nodes, trouvé: $NODE_COUNT"
fi

# Vérifier que tous les nodes sont Ready
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v "Ready" | wc -l)
if [[ "$NOT_READY" -eq 0 ]]; then
    check_pass "Tous les nodes sont Ready"
else
    check_fail "$NOT_READY node(s) non Ready"
fi

kubectl get nodes -o wide
echo ""

# --- 2. Pods système ---------------------------------------------------------
echo "--- Pods système (kube-system) ---"

# Attendre que tous les pods système soient prêts
PENDING=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
if [[ "$PENDING" -eq 0 ]]; then
    check_pass "Tous les pods kube-system sont Running"
else
    check_warn "$PENDING pod(s) kube-system non Running"
    kubectl get pods -n kube-system | grep -v "Running\|Completed"
fi

# Vérifier CoreDNS
COREDNS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep "Running" | wc -l)
if [[ "$COREDNS" -ge 1 ]]; then
    check_pass "CoreDNS fonctionnel ($COREDNS instance(s))"
else
    check_fail "CoreDNS non fonctionnel"
fi

# Vérifier metrics-server
METRICS=$(kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | grep "Running" | wc -l)
if [[ "$METRICS" -ge 1 ]]; then
    check_pass "Metrics Server fonctionnel"
else
    check_warn "Metrics Server non détecté (kubectl top ne fonctionnera pas)"
fi

echo ""

# --- 3. Réseau ---------------------------------------------------------------
echo "--- Réseau ---"

# Test DNS interne
DNS_TEST=$(kubectl run -i --rm --restart=Never dns-test --image=busybox:1.36 -- \
    nslookup kubernetes.default.svc.cluster.local 2>/dev/null | grep -c "Address" || true)
if [[ "$DNS_TEST" -ge 1 ]]; then
    check_pass "DNS cluster fonctionnel (kubernetes.default résolu)"
else
    check_warn "Test DNS échoué (peut être un timing - réessayer)"
fi

# Vérifier les CIDR réseau
POD_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m1 "cluster-cidr" | grep -oP '[\d./]+' || echo "non détecté")
log_check "Pod CIDR: $POD_CIDR"

SVC_CIDR=$(kubectl cluster-info dump 2>/dev/null | grep -m1 "service-cluster-ip-range" | grep -oP '[\d./]+' || echo "non détecté")
log_check "Service CIDR: $SVC_CIDR"

echo ""

# --- 4. Stockage -------------------------------------------------------------
echo "--- Stockage ---"

SC_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
if [[ "$SC_COUNT" -ge 1 ]]; then
    check_pass "StorageClass disponible ($SC_COUNT)"
    kubectl get storageclass
else
    check_warn "Aucune StorageClass détectée"
fi

echo ""

# --- 5. Capacité des nodes ---------------------------------------------------
echo "--- Capacité des nodes ---"

# Vérifier les resources disponibles
kubectl top nodes 2>/dev/null || log_warn "kubectl top non disponible (metrics-server requis)"

echo ""

# --- 6. Labels des nodes -----------------------------------------------------
echo "--- Labels des nodes ---"

for node in $(kubectl get nodes -o name); do
    NODE_NAME=$(echo "$node" | cut -d'/' -f2)
    ROLE=$(kubectl get "$node" -o jsonpath='{.metadata.labels.node-role}' 2>/dev/null || echo "non défini")
    SIZE=$(kubectl get "$node" -o jsonpath='{.metadata.labels.node-size}' 2>/dev/null || echo "non défini")
    log_check "$NODE_NAME: role=$ROLE, size=$SIZE"
done

echo ""

# --- 7. Volumes Hetzner montés -----------------------------------------------
echo "--- Volumes Hetzner ---"

MOUNTED_VOLS=$(lsblk -o NAME,SIZE,MOUNTPOINT | grep -c "/mnt" || echo "0")
log_check "Volumes montés sur ce node: $MOUNTED_VOLS"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -E "sd[b-z]|NAME" || true

echo ""

# --- 8. Version K3s ----------------------------------------------------------
echo "--- Versions ---"

K3S_VER=$(k3s --version 2>/dev/null | head -1 || echo "non détecté")
KUBE_VER=$(kubectl version --short 2>/dev/null || kubectl version 2>/dev/null | head -2 || echo "non détecté")
log_check "K3s: $K3S_VER"
log_check "Kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"

echo ""

# --- Résumé -------------------------------------------------------------------
echo "============================================"
echo "  Résumé"
echo "============================================"
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    log_info "Toutes les vérifications ont réussi !"
elif [[ $ERRORS -eq 0 ]]; then
    log_warn "$WARNINGS avertissement(s), 0 erreur"
else
    log_error "$ERRORS erreur(s), $WARNINGS avertissement(s)"
fi

echo ""
echo "Prochaine étape:"
echo "  cd scripts/bootstrap && ./bootstrap.sh --env production"
echo ""

exit $ERRORS
