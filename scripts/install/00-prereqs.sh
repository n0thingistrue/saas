#!/usr/bin/env bash
# =============================================================================
# Prérequis système pour K3s
# =============================================================================
# Installe et configure les prérequis sur les 2 nodes avant K3s.
# À exécuter en SSH sur chaque node (ou via le cloud-init Terraform).
#
# Ce script est idempotent : peut être relancé sans casser l'existant.
#
# Usage:
#   ./00-prereqs.sh [--node1-ip <ip>] [--node2-ip <ip>]
#   ./00-prereqs.sh --help
# =============================================================================
set -euo pipefail

# --- Configuration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/common.sh" 2>/dev/null || true

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- Help --------------------------------------------------------------------
show_help() {
    cat << 'EOF'
Usage: ./00-prereqs.sh [OPTIONS]

Installe les prérequis système pour K3s sur le node courant.

Options:
  --help          Afficher cette aide
  --skip-update   Ne pas faire apt update/upgrade
  --dry-run       Afficher les commandes sans les exécuter

Prérequis:
  - Debian 12 ou Ubuntu 22.04+
  - Accès root
  - Connexion internet

Ce script configure:
  - Modules kernel (br_netfilter, overlay, ip_tables)
  - Paramètres sysctl (forwarding, performances réseau, sécurité)
  - Paquets système (wireguard, fail2ban, open-iscsi, etc.)
  - Durcissement SSH
  - Configuration NTP
EOF
    exit 0
}

# --- Parse arguments ---------------------------------------------------------
SKIP_UPDATE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help) show_help ;;
        --skip-update) SKIP_UPDATE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) log_error "Option inconnue: $1"; show_help ;;
    esac
done

# --- Vérifications -----------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    log_error "Ce script doit être exécuté en tant que root"
    exit 1
fi

log_info "=== Installation des prérequis K3s ==="
log_info "Hostname: $(hostname)"
log_info "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
log_info "Kernel: $(uname -r)"

# --- 1. Mise à jour système --------------------------------------------------
if [[ "$SKIP_UPDATE" == false ]]; then
    log_info "[1/7] Mise à jour du système..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
else
    log_warn "[1/7] Mise à jour système ignorée (--skip-update)"
fi

# --- 2. Installation des paquets ---------------------------------------------
log_info "[2/7] Installation des paquets requis..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl \
    wget \
    gnupg2 \
    apt-transport-https \
    ca-certificates \
    software-properties-common \
    wireguard \
    wireguard-tools \
    fail2ban \
    ufw \
    jq \
    htop \
    iotop \
    net-tools \
    open-iscsi \
    nfs-common \
    unattended-upgrades \
    apparmor \
    apparmor-utils \
    logrotate \
    chrony \
    rsync \
    tree

# --- 3. Modules kernel -------------------------------------------------------
log_info "[3/7] Configuration des modules kernel..."
cat > /etc/modules-load.d/k3s.conf << 'EOF'
# Modules requis par K3s et le réseau de conteneurs
br_netfilter
overlay
ip_tables
iptable_filter
iptable_nat
iptable_mangle
EOF

# Charger les modules immédiatement
modprobe br_netfilter
modprobe overlay
modprobe ip_tables 2>/dev/null || true
modprobe iptable_filter 2>/dev/null || true
modprobe iptable_nat 2>/dev/null || true

# --- 4. Paramètres sysctl ----------------------------------------------------
log_info "[4/7] Configuration des paramètres sysctl..."
cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
# ===========================================================================
# Paramètres kernel optimisés pour K3s
# ===========================================================================

# --- Forwarding (requis pour K3s) ---
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# --- Performances réseau ---
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1

# --- Buffers réseau ---
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# --- inotify (monitoring / logs) ---
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# --- File descriptors ---
fs.file-max = 2097152

# --- Sécurité réseau ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1

# --- Protection SYN flood ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_orphans = 65535

# --- Mémoire virtuelle ---
vm.max_map_count = 262144
vm.swappiness = 10
vm.overcommit_memory = 1
EOF

# Appliquer immédiatement
sysctl --system > /dev/null 2>&1

# --- 5. Durcissement SSH -----------------------------------------------------
log_info "[5/7] Durcissement SSH..."
cat > /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
# Durcissement SSH - RNCP37680
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
AllowAgentForwarding no
AllowTcpForwarding no
EOF

systemctl restart sshd

# --- 6. Configuration fail2ban ------------------------------------------------
log_info "[6/7] Configuration fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd
banaction = iptables-multiport

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

systemctl enable --now fail2ban

# --- 7. Configuration NTP (chrony) -------------------------------------------
log_info "[7/7] Configuration NTP..."
cat > /etc/chrony/chrony.conf << 'EOF'
# Serveurs NTP Hetzner
server ntp1.hetzner.de iburst
server ntp2.hetzner.com iburst
server ntp3.hetzner.net iburst

# Fallback pool
pool 2.debian.pool.ntp.org iburst

driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

systemctl enable --now chrony

# --- Vérifications finales ---------------------------------------------------
log_info ""
log_info "=== Vérifications ==="
log_info "Modules kernel chargés:"
for mod in br_netfilter overlay; do
    if lsmod | grep -q "$mod"; then
        log_info "  ✓ $mod"
    else
        log_error "  ✗ $mod (MANQUANT)"
    fi
done

log_info "IP forwarding: $(sysctl -n net.ipv4.ip_forward)"
log_info "fail2ban: $(systemctl is-active fail2ban)"
log_info "chrony: $(systemctl is-active chrony)"
log_info ""
log_info "=== Prérequis installés avec succès ==="
log_info "Prochaine étape: ./01-install-k3s-server.sh (sur Node 1)"
