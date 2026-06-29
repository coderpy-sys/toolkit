#!/usr/bin/env bash
# ============================================================
#   ✦ POTTERHEAD SERVER TOOLKIT ✦
#   Made with ♥ by @thatonepotterhead
#   github.com/thatonepotterhead
#   curl -fsSL https://get.goatdead.com | bash
# ============================================================

# ── Pipe detection: re-exec from temp file if stdin is a pipe ──
if [ ! -t 0 ]; then
    TMPFILE=$(mktemp /tmp/ph.XXXXXX.sh)
    cat > "$TMPFILE"
    chmod +x "$TMPFILE"
    bash "$TMPFILE" "$@" < /dev/tty
    EXIT_CODE=$?
    rm -f "$TMPFILE" 2>/dev/null
    exit $EXIT_CODE
fi

set -uo pipefail

# ── Colours & typography ────────────────────────────────────
R='\033[0;31m'  G='\033[0;32m'  Y='\033[1;33m'
B='\033[0;34m'  C='\033[0;36m'  M='\033[0;35m'
W='\033[1;37m'  DIM='\033[2m'   BOLD='\033[1m'
NC='\033[0m'

ok()      { echo -e "  ${G}✓${NC}  $*"; }
info()    { echo -e "  ${C}→${NC}  $*"; }
warn()    { echo -e "  ${Y}!${NC}  $*"; }
err()     { echo -e "  ${R}✗${NC}  $*" >&2; }
die()     { err "$*"; exit 1; }
sep()     { echo -e "  ${DIM}────────────────────────────────────────────${NC}"; }
hdr()     { echo -e "\n  ${W}${BOLD}$*${NC}"; sep; }

clear_screen() { printf '\033[2J\033[H'; }

brand() {
  clear_screen
  echo -e "${M}${BOLD}"
  echo '  ██████╗  ██████╗ ████████╗████████╗███████╗██████╗ ██╗  ██╗███████╗ █████╗ ██████╗ '
  echo '  ██╔══██╗██╔═══██╗╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗██║  ██║██╔════╝██╔══██╗██╔══██╗'
  echo '  ██████╔╝██║   ██║   ██║      ██║   █████╗  ██████╔╝███████║█████╗  ███████║██║  ██║'
  echo '  ██╔═══╝ ██║   ██║   ██║      ██║   ██╔══╝  ██╔══██╗██╔══██║██╔══╝  ██╔══██║██║  ██║'
  echo '  ██║     ╚██████╔╝   ██║      ██║   ███████╗██║  ██║██║  ██║███████╗██║  ██║██████╔╝'
  echo '  ╚═╝      ╚═════╝    ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ '
  echo -e "${NC}"
  echo -e "  ${DIM}Server Toolkit  •  Made with ♥ by ${W}@thatonepotterhead${NC}"
  echo -e "  ${DIM}Run:  ${C}curl -fsSL https://get.goatdead.com | bash${NC}"
  echo
}

pause()   { echo; read -rp "  $(echo -e "${DIM}Press Enter to continue...${NC}")" _; }
confirm() {
  local msg="${1:-Are you sure?}"
  echo
  read -rp "  $(echo -e "${Y}?${NC}  ${msg} ${DIM}[y/N]${NC}: ")" ans
  [[ "${ans,,}" =~ ^y(es)?$ ]]
}

pick_ct_id() {
  local id="${1:-200}"
  while pct status "$id" &>/dev/null || qm status "$id" &>/dev/null; do ((id++)); done
  echo "$id"
}

# ════════════════════════════════════════════════════════════
#  OPTION 1 — Install Proxmox VE on bare Debian
# ════════════════════════════════════════════════════════════
install_proxmox() {
  brand
  hdr "Option 1 — Install Proxmox VE"
  echo -e "  This will install ${W}Proxmox VE${NC} on a bare Debian 12/13 machine."
  echo -e "  ${DIM}Requirements: Debian 12 or 13, root access, internet connection.${NC}"
  echo
  confirm "Continue with Proxmox installation?" || { info "Aborted."; return; }

  hdr "Step 1 — Detecting Debian version"
  command -v lsb_release &>/dev/null || apt-get install -y lsb-release &>/dev/null
  local DEBIAN_VERSION REPO_CODENAME
  DEBIAN_VERSION=$(lsb_release -rs 2>/dev/null | cut -d. -f1)
  case "$DEBIAN_VERSION" in
    12) REPO_CODENAME="bookworm" ;;
    13) REPO_CODENAME="trixie"   ;;
    *)  die "Only Debian 12 or 13 supported (detected: $DEBIAN_VERSION)" ;;
  esac
  ok "Debian ${DEBIAN_VERSION} (${REPO_CODENAME}) detected"

  hdr "Step 2 — Adding Proxmox repository"
  echo "deb [arch=amd64] http://download.proxmox.com/debian/pve ${REPO_CODENAME} pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-install-repo.list
  wget -q "https://enterprise.proxmox.com/debian/proxmox-release-${REPO_CODENAME}.gpg" \
    -O "/etc/apt/trusted.gpg.d/proxmox-release-${REPO_CODENAME}.gpg"
  ok "Repository and GPG key added"

  hdr "Step 3 — System upgrade"
  apt-get update -y && apt-get dist-upgrade -y
  ok "System upgraded"

  hdr "Step 4 — Installing Proxmox kernel"
  apt-get install -y proxmox-default-kernel
  ok "Proxmox kernel installed"

  hdr "Step 5 — Installing Proxmox VE"
  DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi
  apt-get remove -y os-prober 2>/dev/null || true
  ok "Proxmox VE installed"

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║   Proxmox VE installed successfully!         ║${NC}"
  echo -e "  ${G}${BOLD}║                                              ║${NC}"
  echo -e "  ${G}${BOLD}║   Reboot now, then access:                   ║${NC}"
  echo -e "  ${G}${BOLD}║   https://YOUR_IP:8006                       ║${NC}"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo
  confirm "Reboot now?" && reboot
}

# ════════════════════════════════════════════════════════════
#  OPTION 2 — Fresh Proxmox network setup
# ════════════════════════════════════════════════════════════
setup_proxmox_network() {
  brand
  hdr "Option 2 — Proxmox Network Setup"
  echo -e "  Sets up ${W}vmbr0${NC} (public bridge) and ${W}vmbr1${NC} (private NAT bridge)."
  echo

  hdr "Network Information"
  local detected_nic
  detected_nic=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|vmbr|veth|tap|dummy|docker|gre)/ {print $2}' | head -1)
  echo -e "  ${DIM}Detected NIC: ${W}${detected_nic}${NC}"
  read -rp "  $(echo -e "${W}Physical NIC${NC} ${DIM}[${detected_nic}]${NC}: ")" NIC_INPUT
  local NIC="${NIC_INPUT:-$detected_nic}"
  ok "Using NIC: $NIC"
  echo

  local detected_ip detected_gw detected_prefix
  detected_ip=$(ip -4 addr show "$NIC" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  detected_gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
  detected_prefix=$(echo "$detected_ip" | cut -d'/' -f2)
  detected_ip=$(echo "$detected_ip" | cut -d'/' -f1)

  read -rp "  $(echo -e "${W}Host IP address${NC} ${DIM}[${detected_ip}]${NC}: ")" IP_INPUT
  local HOST_IP="${IP_INPUT:-$detected_ip}"
  read -rp "  $(echo -e "${W}Prefix length${NC} ${DIM}[${detected_prefix:-24}]${NC}: ")" PREFIX_INPUT
  local PREFIX="${PREFIX_INPUT:-${detected_prefix:-24}}"
  read -rp "  $(echo -e "${W}Gateway${NC} ${DIM}[${detected_gw}]${NC}: ")" GW_INPUT
  local GW="${GW_INPUT:-$detected_gw}"
  read -rp "  $(echo -e "${W}DNS servers${NC} ${DIM}[1.1.1.1 8.8.8.8]${NC}: ")" DNS_INPUT
  local DNS="${DNS_INPUT:-1.1.1.1 8.8.8.8}"

  hdr "Private Bridge (vmbr1)"
  echo -e "  ${DIM}Internal NAT bridge. Default: 10.0.0.1/24, VM range 10.0.0.10–250${NC}"
  echo
  read -rp "  $(echo -e "${W}vmbr1 gateway IP${NC} ${DIM}[10.0.0.1]${NC}: ")" VMBR1_GW_INPUT
  local VMBR1_GW="${VMBR1_GW_INPUT:-10.0.0.1}"
  local VMBR1_NET; VMBR1_NET=$(echo "$VMBR1_GW" | awk -F'.' '{printf "%s.%s.%s.0/24",$1,$2,$3}')

  echo
  echo -e "  ${W}${BOLD}Summary${NC}"; sep
  echo -e "  NIC          ${C}${NIC}${NC}"
  echo -e "  vmbr0 IP     ${C}${HOST_IP}/${PREFIX}${NC}"
  echo -e "  Gateway      ${C}${GW}${NC}"
  echo -e "  DNS          ${C}${DNS}${NC}"
  echo -e "  vmbr1        ${C}${VMBR1_GW}/24${NC}  ${DIM}(NAT → vmbr0)${NC}"
  echo
  confirm "Write configuration and reload networking?" || { info "Aborted."; return; }

  hdr "Writing /etc/network/interfaces"
  local BACKUP="/etc/network/interfaces.bak.$(date +%s)"
  [[ -f /etc/network/interfaces ]] && cp /etc/network/interfaces "$BACKUP" && ok "Backup → $BACKUP"

  if [[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]]; then
    sed -i "s/data.status !== 'Active'/false/g" \
      /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true
    ok "Subscription nag removed"
  fi

  cat > /etc/network/interfaces << EOF
# ╔══════════════════════════════════════════╗
# ║  POTTERHEAD — /etc/network/interfaces   ║
# ║  Generated: $(date)
# ╚══════════════════════════════════════════╝

auto lo
iface lo inet loopback

iface ${NIC} inet manual

auto vmbr0
iface vmbr0 inet static
    address ${HOST_IP}/${PREFIX}
    gateway ${GW}
    bridge-ports ${NIC}
    bridge-stp off
    bridge-fd 0
    dns-nameservers ${DNS}
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward

# vmbr1: Private NAT bridge — ${VMBR1_GW}/24
# VM range: $(echo "$VMBR1_GW" | awk -F'.' '{printf "%s.%s.%s",$1,$2,$3}').10 – .250
auto vmbr1
iface vmbr1 inet static
    address ${VMBR1_GW}/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -A POSTROUTING -s ${VMBR1_NET} -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s ${VMBR1_NET} -o vmbr0 -j MASQUERADE
EOF
  ok "/etc/network/interfaces written"

  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-potterhead.conf
  sysctl -p /etc/sysctl.d/99-potterhead.conf &>/dev/null
  ok "ip_forward=1 persisted"

  if ! dpkg -l iptables-persistent &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent &>/dev/null
  fi

  ifreload -a 2>/dev/null || true

  if ! ip link show vmbr1 &>/dev/null; then
    ip link add name vmbr1 type bridge 2>/dev/null || true
    ip addr add "${VMBR1_GW}/24" dev vmbr1 2>/dev/null || true
    ip link set vmbr1 up 2>/dev/null || true
  fi
  iptables -t nat -D POSTROUTING -s "${VMBR1_NET}" -o vmbr0 -j MASQUERADE 2>/dev/null || true
  iptables -t nat -A POSTROUTING -s "${VMBR1_NET}" -o vmbr0 -j MASQUERADE
  netfilter-persistent save &>/dev/null || true
  ok "Network live and persistent"

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║   Network configured!                        ║${NC}"
  printf   "  ${G}${BOLD}║   vmbr0  →  %-32s║${NC}\n" "${HOST_IP}/${PREFIX}"
  printf   "  ${G}${BOLD}║   vmbr1  →  %-32s║${NC}\n" "${VMBR1_GW}/24 (NAT)"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo
  pause
}

# ════════════════════════════════════════════════════════════
#  OPTION 3 — Install Convoy Panel
# ════════════════════════════════════════════════════════════
install_convoy() {
  brand
  hdr "Option 3 — Install Convoy Panel"
  echo -e "  Creates a ${W}Debian 12 LXC${NC} and installs Convoy Panel inside it."
  echo -e "  ${DIM}Run this on the Proxmox host.${NC}"
  echo
  command -v pct   &>/dev/null || die "pct not found — run on Proxmox host"
  command -v pveum &>/dev/null || die "pveum not found"

  hdr "Container Settings"
  read -rp "  $(echo -e "${W}Bridge${NC} ${DIM}[vmbr1]${NC}: ")" BR_IN
  local CT_BRIDGE="${BR_IN:-vmbr1}"
  ip link show "$CT_BRIDGE" &>/dev/null || die "Bridge $CT_BRIDGE does not exist"

  while true; do
    read -rp "  $(echo -e "${W}Container IP/CIDR${NC} ${DIM}(e.g. 10.0.0.50/24)${NC}: ")" CT_CIDR
    CT_CIDR="${CT_CIDR// /}"
    [[ "$CT_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] && break
    warn "Invalid — use x.x.x.x/xx"
  done
  local CT_IP="${CT_CIDR%%/*}"

  local default_gw; default_gw=$(printf "%s" "$CT_IP" | awk -F'.' '{printf "%s.%s.%s.1",$1,$2,$3}')
  read -rp "  $(echo -e "${W}Gateway${NC} ${DIM}[${default_gw}]${NC}: ")" GW_IN
  local CT_GW="${GW_IN:-$default_gw}"

  read -rp "  $(echo -e "${W}Storage${NC} ${DIM}[local]${NC}: ")" ST_IN
  local CT_STORAGE="${ST_IN:-local}"
  read -rp "  $(echo -e "${W}RAM (MB)${NC} ${DIM}[4096]${NC}: ")" RAM_IN
  local CT_RAM="${RAM_IN:-4096}"
  read -rp "  $(echo -e "${W}Disk (GB)${NC} ${DIM}[20]${NC}: ")" DISK_IN
  local CT_DISK="${DISK_IN:-20}"
  read -rp "  $(echo -e "${W}CPU cores${NC} ${DIM}[2]${NC}: ")" CORES_IN
  local CT_CORES="${CORES_IN:-2}"
  read -rp "  $(echo -e "${W}Hostname${NC} ${DIM}[convoy-panel]${NC}: ")" HN_IN
  local CT_HOSTNAME="${HN_IN:-convoy-panel}"

  hdr "Convoy Admin Account"
  read -rp "  $(echo -e "${W}Admin email${NC} ${DIM}[admin@admin.com]${NC}: ")" EMAIL_IN
  local CONVOY_EMAIL="${EMAIL_IN:-admin@admin.com}"
  read -rp "  $(echo -e "${W}Admin username${NC} ${DIM}[admin]${NC}: ")" USER_IN
  local CONVOY_USER="${USER_IN:-admin}"
  read -rsp "  $(echo -e "${W}Admin password${NC}: ")" CONVOY_PASS; echo
  [[ -z "$CONVOY_PASS" ]] && CONVOY_PASS="admin" && warn "No password — using 'admin'"

  echo
  echo -e "  ${W}${BOLD}Summary${NC}"; sep
  echo -e "  Hostname     ${C}${CT_HOSTNAME}${NC}"
  echo -e "  IP/CIDR      ${C}${CT_CIDR}${NC}  Gateway ${C}${CT_GW}${NC}"
  echo -e "  Bridge       ${C}${CT_BRIDGE}${NC}  Storage ${C}${CT_STORAGE}${NC}"
  echo -e "  Resources    ${C}${CT_CORES} vCPU / ${CT_RAM}MB RAM / ${CT_DISK}GB disk${NC}"
  echo -e "  Admin        ${C}${CONVOY_USER} <${CONVOY_EMAIL}>${NC}"
  echo
  confirm "Create container and install Convoy?" || { info "Aborted."; return; }

  local CT_ID; CT_ID=$(pick_ct_id 200)
  info "Using CT ID: $CT_ID"
  local CT_ROOT_PASS; CT_ROOT_PASS=$(openssl rand -base64 18 | tr -d '=/+' | head -c 20)

  local SSH_KEY="/root/.ssh/convoy_${CT_ID}_ed25519"
  mkdir -p /root/.ssh; chmod 700 /root/.ssh
  ssh-keygen -t ed25519 -C "convoy-${CT_ID}" -f "$SSH_KEY" -N "" -q
  ok "SSH key → $SSH_KEY"

  hdr "Downloading Debian 12 template"
  local TEMPLATE
  TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
  if [[ -z "$TEMPLATE" ]]; then
    pveam update &>/dev/null
    local AVAIL; AVAIL=$(pveam available --section system 2>/dev/null | awk '{print $2}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
    [[ -n "$AVAIL" ]] || die "No Debian 12 template found"
    pveam download "$CT_STORAGE" "$AVAIL"
    TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1)
  fi
  ok "Template: $TEMPLATE"

  hdr "Creating and starting CT${CT_ID}"
  pct create "$CT_ID" "$TEMPLATE" \
    --hostname "$CT_HOSTNAME" --cores "$CT_CORES" --memory "$CT_RAM" --swap 512 \
    --rootfs "${CT_STORAGE}:${CT_DISK}" \
    --net0 "name=eth0,bridge=${CT_BRIDGE},ip=${CT_CIDR},gw=${CT_GW}" \
    --nameserver "1.1.1.1 8.8.8.8" --unprivileged 0 \
    --features "nesting=1,keyctl=1" \
    --password "$CT_ROOT_PASS" --ssh-public-keys "${SSH_KEY}.pub" \
    --onboot 1 --start 0
  printf 'lxc.cgroup2.devices.allow = c 10:200 rwm\nlxc.mount.entry = /dev/net/tun dev/net/tun none bind,create=file\n' \
    >> "/etc/pve/lxc/${CT_ID}.conf"
  pct start "$CT_ID"
  info "Waiting for CT..."
  local attempt
  for ((attempt=1; attempt<=30; attempt++)); do
    pct exec "$CT_ID" -- bash -c 'exit 0' &>/dev/null && { ok "CT ready"; break; }
    sleep 2; ((attempt==30)) && die "CT did not start"
  done

  hdr "Installing Docker + Convoy Panel"
  pct exec "$CT_ID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get upgrade -y --no-install-recommends
    apt-get install -y --no-install-recommends curl wget ca-certificates gnupg tar jq openssl git procps
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker && systemctl start docker
  "
  for ((attempt=1; attempt<=18; attempt++)); do
    pct exec "$CT_ID" -- docker info &>/dev/null && { ok "Docker running"; break; }
    sleep 5; ((attempt==18)) && die "Docker did not start"
  done
  pct exec "$CT_ID" -- bash -c "
    curl -fsSL https://raw.githubusercontent.com/convoypanel/panel/develop/scripts/install.sh \
      -o /root/install_convoy.sh 2>/dev/null \
    || curl -fsSL https://raw.githubusercontent.com/oneclickvirt/convoypanel-scripts/main/install_convoy.sh \
      -o /root/install_convoy.sh
    chmod +x /root/install_convoy.sh && bash /root/install_convoy.sh 2>&1
  " || warn "Installer non-zero — check CT console"

  pct exec "$CT_ID" -- bash -c "
    cd /var/www/convoy 2>/dev/null || cd /srv/convoy 2>/dev/null || true
    printf '%s\n%s\n%s\n%s\nyes\n' 'Admin' '${CONVOY_EMAIL}' '${CONVOY_USER}' '${CONVOY_PASS}' \
      | docker compose exec -T workspace php artisan c:user:make 2>&1
  " && ok "Admin user created" || warn "Admin creation may need manual retry"

  hdr "Creating PVE API token"
  pveum user token remove "root@pam" "convoy" &>/dev/null || true
  local TOKEN_JSON TOKEN_VALUE TOKEN_ID_FULL
  TOKEN_JSON=$(pveum user token add "root@pam" "convoy" --privsep=0 --output-format=json)
  TOKEN_VALUE=$(echo "$TOKEN_JSON" | jq -er '.value // empty' 2>/dev/null || echo "$TOKEN_JSON" | grep -oP '"value"\s*:\s*"\K[^"]+')
  TOKEN_ID_FULL=$(echo "$TOKEN_JSON" | jq -er '."full-tokenid" // empty' 2>/dev/null || echo "$TOKEN_JSON" | grep -oP '"full-tokenid"\s*:\s*"\K[^"]+')

  local TOKEN_FILE="/root/convoy-token-${CT_ID}.txt"
  { echo "CT ID      : $CT_ID"; echo "CT IP      : $CT_IP"; echo "Panel URL  : http://$CT_IP"
    echo "Token ID   : $TOKEN_ID_FULL"; echo "Secret     : $TOKEN_VALUE"
    echo "Root pass  : $CT_ROOT_PASS"; echo "SSH key    : $SSH_KEY"; } > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"; ok "Token saved → $TOKEN_FILE"

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║             Convoy Panel — Installation Complete             ║${NC}"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf   "  ${G}${BOLD}║  Panel URL   : %-46s║${NC}\n" "http://$CT_IP"
  printf   "  ${G}${BOLD}║  Email       : %-46s║${NC}\n" "$CONVOY_EMAIL"
  printf   "  ${G}${BOLD}║  Username    : %-46s║${NC}\n" "$CONVOY_USER"
  printf   "  ${G}${BOLD}║  Password    : %-46s║${NC}\n" "$CONVOY_PASS"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf   "  ${G}${BOLD}║  Token ID    : %-46s║${NC}\n" "${TOKEN_ID_FULL:-see $TOKEN_FILE}"
  printf   "  ${G}${BOLD}║  Secret      : %-46s║${NC}\n" "${TOKEN_VALUE:-see $TOKEN_FILE}"
  printf   "  ${G}${BOLD}║  Root pass   : %-46s║${NC}\n" "$CT_ROOT_PASS"
  printf   "  ${G}${BOLD}║  Saved to    : %-46s║${NC}\n" "$TOKEN_FILE"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo
  pause
}

# ════════════════════════════════════════════════════════════
#  OPTION 4 — Fix Networking
# ════════════════════════════════════════════════════════════
fix_networking() {
  brand
  hdr "Option 4 — Fix Networking"

  echo -e "  This tool will:"
  echo -e "  ${C}1${NC}  Read your current network state"
  echo -e "  ${C}2${NC}  Let you pick which bridge to fix"
  echo -e "  ${C}3${NC}  Spin up a temporary test CT to validate connectivity"
  echo -e "  ${C}4${NC}  Apply the fix to the real bridge if the test passes"
  echo -e "  ${C}5${NC}  Destroy the temp CT"
  echo
  command -v pct &>/dev/null || die "pct not found — run on Proxmox host"

  # ── PHASE 1: Read current state ──────────────────────────
  hdr "Phase 1 — Reading Current Network State"

  echo -e "\n  ${W}Bridges detected:${NC}"
  sep
  local bridges=()
  while IFS= read -r br; do
    bridges+=("$br")
    local br_ip; br_ip=$(ip -4 addr show "$br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    local br_ports; br_ports=$(brctl show "$br" 2>/dev/null | awk 'NR>1 && $NF!="" {print $NF}' | tr '\n' ' ' | sed 's/ $//')
    local br_vms; br_vms=$(ip link show 2>/dev/null | grep -oP "(?<=master ${br} ).+" | head -3 | tr '\n' ' ' | sed 's/ $//')
    printf "  ${C}%-10s${NC}  IP: ${W}%-20s${NC}  Ports: ${DIM}%-15s${NC}  VMs/CTs: ${DIM}%s${NC}\n" \
      "$br" "${br_ip:-(none)}" "${br_ports:-(none)}" "${br_vms:-(none)}"
  done < <(ip link show type bridge 2>/dev/null | awk -F': ' '/^[0-9]+:/{print $2}' | grep -v '^$')

  echo
  echo -e "  ${W}Current /etc/network/interfaces:${NC}"
  sep
  cat /etc/network/interfaces | sed 's/^/  /'
  echo

  echo -e "  ${W}Policy routing rules:${NC}"
  sep
  ip rule show | sed 's/^/  /'
  echo

  echo -e "  ${W}iptables NAT rules:${NC}"
  sep
  iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null | sed 's/^/  /' || true
  echo

  echo -e "  ${W}ip_forward:${NC} $(cat /proc/sys/net/ipv4/ip_forward)"
  echo

  # ── PHASE 2: Pick bridge ─────────────────────────────────
  hdr "Phase 2 — Select Bridge to Fix"

  if [[ ${#bridges[@]} -eq 0 ]]; then
    die "No bridges found on this system"
  fi

  echo -e "  ${DIM}Available bridges:${NC}"
  local i=1
  for br in "${bridges[@]}"; do
    local br_ip; br_ip=$(ip -4 addr show "$br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    echo -e "  ${M}${BOLD}  $i${NC}  ${W}${br}${NC}  ${DIM}${br_ip:-(no ip)}${NC}"
    ((i++))
  done
  echo

  local sel_br
  while true; do
    read -rp "  $(echo -e "${W}Pick bridge number to fix${NC}: ")" sel_num
    if [[ "$sel_num" =~ ^[0-9]+$ ]] && (( sel_num >= 1 && sel_num <= ${#bridges[@]} )); then
      sel_br="${bridges[$((sel_num-1))]}"
      break
    fi
    warn "Enter a number between 1 and ${#bridges[@]}"
  done
  ok "Selected: $sel_br"

  # ── PHASE 3: Desired config ──────────────────────────────
  hdr "Phase 3 — Desired Configuration for ${sel_br}"

  local cur_ip; cur_ip=$(ip -4 addr show "$sel_br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  local cur_gw; cur_gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)

  echo -e "  ${DIM}Current IP on ${sel_br}: ${cur_ip:-(none)}${NC}"
  echo

  read -rp "  $(echo -e "${W}New IP/CIDR for ${sel_br}${NC} ${DIM}[${cur_ip:-10.0.0.1/24}]${NC}: ")" NEW_CIDR_IN
  local NEW_CIDR="${NEW_CIDR_IN:-${cur_ip:-10.0.0.1/24}}"
  local NEW_IP="${NEW_CIDR%%/*}"
  local NEW_PREFIX="${NEW_CIDR##*/}"
  local NEW_NET; NEW_NET=$(python3 -c "import ipaddress; n=ipaddress.ip_interface('${NEW_CIDR}'); print(str(n.network))" 2>/dev/null \
    || echo "$(echo "$NEW_IP" | awk -F'.' '{printf "%s.%s.%s",$1,$2,$3}').0/${NEW_PREFIX}")

  local NEW_GW=""
  if [[ "$sel_br" == "vmbr0" ]]; then
    read -rp "  $(echo -e "${W}Gateway${NC} ${DIM}[${cur_gw}]${NC}: ")" NEW_GW_IN
    NEW_GW="${NEW_GW_IN:-$cur_gw}"
  fi

  local DO_NAT="no"
  if [[ "$sel_br" != "vmbr0" ]]; then
    read -rp "  $(echo -e "${W}Enable NAT masquerade → vmbr0?${NC} ${DIM}[Y/n]${NC}: ")" NAT_IN
    [[ "${NAT_IN,,}" =~ ^(y|yes|)$ ]] && DO_NAT="yes"
  fi

  # ── PHASE 4: Temp test CT ────────────────────────────────
  hdr "Phase 4 — Spinning Up Temp Test CT"

  local TEST_HOST_OCTET=199
  local TEST_IP; TEST_IP=$(echo "$NEW_IP" | awk -F'.' "{printf \"%s.%s.%s.${TEST_HOST_OCTET}\",\$1,\$2,\$3}")
  local TEST_GW="$NEW_IP"
  local TEST_CIDR="${TEST_IP}/${NEW_PREFIX}"

  echo -e "  ${DIM}Test CT will use: ${W}${TEST_CIDR}${NC}  gw ${W}${TEST_GW}${NC}${NC}"
  echo

  local TEMP_ID; TEMP_ID=$(pick_ct_id 900)
  info "Temp CT ID: $TEMP_ID"

  local CT_STORAGE="local"
  local TEMPLATE
  TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
  if [[ -z "$TEMPLATE" ]]; then
    info "Downloading Debian 12 template..."
    pveam update &>/dev/null
    local AVAIL; AVAIL=$(pveam available --section system 2>/dev/null | awk '{print $2}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
    [[ -n "$AVAIL" ]] || die "No Debian 12 template available"
    pveam download "$CT_STORAGE" "$AVAIL" || die "Template download failed"
    TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1)
  fi
  ok "Template: $TEMPLATE"

  local TEMP_PASS; TEMP_PASS=$(openssl rand -base64 12 | tr -d '=/+' | head -c 14)

  info "Applying new IP to ${sel_br} for test..."
  ip addr flush dev "$sel_br" 2>/dev/null || true
  ip addr add "${NEW_CIDR}" dev "$sel_br" 2>/dev/null || true
  ip link set "$sel_br" up 2>/dev/null || true

  if [[ "$DO_NAT" == "yes" ]]; then
    iptables -t nat -D POSTROUTING -s "${NEW_NET}" -o vmbr0 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s "${NEW_NET}" -o vmbr0 -j MASQUERADE
    echo 1 > /proc/sys/net/ipv4/ip_forward
    ok "NAT masquerade enabled for test"
  fi

  pct create "$TEMP_ID" "$TEMPLATE" \
    --hostname "ph-nettest-${TEMP_ID}" \
    --cores 1 --memory 256 --swap 0 \
    --rootfs "${CT_STORAGE}:1" \
    --net0 "name=eth0,bridge=${sel_br},ip=${TEST_CIDR},gw=${TEST_GW}" \
    --nameserver "1.1.1.1" \
    --unprivileged 1 --features "nesting=0" \
    --password "$TEMP_PASS" \
    --onboot 0 --start 0 2>/dev/null || {
      warn "CT create failed — cleaning up"
      pct destroy "$TEMP_ID" --purge 2>/dev/null || true
      die "Could not create test CT"
    }

  pct start "$TEMP_ID"
  info "Waiting for temp CT to boot..."
  local attempt
  for ((attempt=1; attempt<=20; attempt++)); do
    pct exec "$TEMP_ID" -- bash -c 'exit 0' &>/dev/null && break
    sleep 2
    ((attempt==20)) && {
      pct stop "$TEMP_ID" &>/dev/null || true
      pct destroy "$TEMP_ID" --purge &>/dev/null || true
      die "Temp CT failed to start"
    }
  done
  ok "Temp CT ${TEMP_ID} is up"

  # ── PHASE 5: Tests ───────────────────────────────────────
  hdr "Phase 5 — Connectivity Tests"

  local TEST_PASS=0 TEST_FAIL=0

  run_test() {
    local label="$1" cmd="$2"
    printf "  %-40s" "$label"
    if pct exec "$TEMP_ID" -- bash -c "$cmd" &>/dev/null; then
      echo -e "${G}PASS${NC}"; ((TEST_PASS++))
    else
      echo -e "${R}FAIL${NC}"; ((TEST_FAIL++))
    fi
  }

  run_test "Ping gateway (${TEST_GW})"           "ping -c 2 -W 3 ${TEST_GW}"
  run_test "Ping Cloudflare DNS (1.1.1.1)"       "ping -c 2 -W 5 1.1.1.1"
  run_test "Ping Google DNS (8.8.8.8)"            "ping -c 2 -W 5 8.8.8.8"
  run_test "DNS resolution (google.com)"          "getent hosts google.com"
  run_test "HTTP connectivity (curl ifconfig.me)" "curl -s --max-time 8 ifconfig.me"

  local CT_PUB_IP
  CT_PUB_IP=$(pct exec "$TEMP_ID" -- bash -c "curl -s --max-time 8 ifconfig.me" 2>/dev/null || echo "unreachable")

  echo
  echo -e "  ${W}Results:${NC}  ${G}${TEST_PASS} passed${NC}  /  ${R}${TEST_FAIL} failed${NC}"
  [[ -n "$CT_PUB_IP" && "$CT_PUB_IP" != "unreachable" ]] && \
    echo -e "  ${W}Public IP seen from CT:${NC} ${C}${CT_PUB_IP}${NC}"
  echo

  # ── PHASE 6: Destroy temp CT ─────────────────────────────
  hdr "Phase 6 — Cleaning Up Temp CT"
  pct stop "$TEMP_ID" --timeout 10 2>/dev/null || true
  sleep 2
  pct destroy "$TEMP_ID" --purge 2>/dev/null || true
  ok "Temp CT ${TEMP_ID} destroyed"

  # ── PHASE 7: Apply permanent fix ─────────────────────────
  hdr "Phase 7 — Apply Permanent Fix"

  if [[ $TEST_FAIL -gt 0 ]]; then
    echo -e "  ${Y}${TEST_FAIL} test(s) failed.${NC} The config may still work partially."
    echo -e "  ${DIM}(Gateway ping failing is normal for private NAT bridges)${NC}"
    echo
  fi

  confirm "Apply this configuration permanently to ${sel_br} and update /etc/network/interfaces?" || {
    warn "Not applying — reverting bridge IP to original"
    ip addr flush dev "$sel_br" 2>/dev/null || true
    [[ -n "$cur_ip" ]] && ip addr add "$cur_ip" dev "$sel_br" 2>/dev/null || true
    [[ "$DO_NAT" == "yes" ]] && iptables -t nat -D POSTROUTING -s "${NEW_NET}" -o vmbr0 -j MASQUERADE 2>/dev/null || true
    info "Reverted. No changes made."
    pause; return
  }

  local BACKUP="/etc/network/interfaces.fix.$(date +%s)"
  cp /etc/network/interfaces "$BACKUP"
  ok "Backup → $BACKUP"

  python3 - "$sel_br" "$NEW_CIDR" "$NEW_GW" "$DO_NAT" "$NEW_NET" << 'PYEOF'
import sys, re

bridge  = sys.argv[1]
cidr    = sys.argv[2]
gw      = sys.argv[3]
do_nat  = sys.argv[4]
net     = sys.argv[5]

with open('/etc/network/interfaces', 'r') as f:
    content = f.read()

pattern = r'(?:^auto\s+{br}\s*\n)?(?:^iface\s+{br}\s+.*?)(?=^auto\s|\Z)'.format(br=re.escape(bridge))
content = re.sub(pattern, '', content, flags=re.MULTILINE | re.DOTALL)
content = content.rstrip('\n') + '\n'

nat_up   = f'    post-up   iptables -t nat -A POSTROUTING -s {net} -o vmbr0 -j MASQUERADE\n' if do_nat == 'yes' else ''
nat_down = f'    post-down iptables -t nat -D POSTROUTING -s {net} -o vmbr0 -j MASQUERADE\n' if do_nat == 'yes' else ''
gw_line  = f'    gateway {gw}\n' if gw else ''

stanza = f"""
auto {bridge}
iface {bridge} inet static
    address {cidr}
{gw_line}    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
{nat_up}{nat_down}"""

with open('/etc/network/interfaces', 'w') as f:
    f.write(content + stanza + '\n')

print('  interfaces file updated')
PYEOF

  ok "/etc/network/interfaces updated"

  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-potterhead.conf
  sysctl -p /etc/sysctl.d/99-potterhead.conf &>/dev/null
  ok "ip_forward=1 persisted"

  if [[ "$DO_NAT" == "yes" ]]; then
    if ! dpkg -l iptables-persistent &>/dev/null; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent &>/dev/null
    fi
    netfilter-persistent save &>/dev/null || true
    ok "iptables rules persisted"
  fi

  ifreload -a 2>/dev/null || true
  ok "Network reloaded"

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║   Network Fix Applied!                       ║${NC}"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════╣${NC}"
  printf   "  ${G}${BOLD}║  Bridge     : %-30s║${NC}\n" "$sel_br"
  printf   "  ${G}${BOLD}║  IP/CIDR    : %-30s║${NC}\n" "$NEW_CIDR"
  [[ -n "$NEW_GW" ]] && printf "  ${G}${BOLD}║  Gateway    : %-30s║${NC}\n" "$NEW_GW"
  printf   "  ${G}${BOLD}║  NAT        : %-30s║${NC}\n" "$DO_NAT"
  printf   "  ${G}${BOLD}║  Tests      : %-30s║${NC}\n" "${TEST_PASS} passed / ${TEST_FAIL} failed"
  printf   "  ${G}${BOLD}║  Backup     : %-30s║${NC}\n" "$BACKUP"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo
  pause
}

# ════════════════════════════════════════════════════════════
#  MAIN MENU
# ════════════════════════════════════════════════════════════
main_menu() {
  while true; do
    brand
    echo -e "  ${W}${BOLD}What do you want to do?${NC}"
    echo
    echo -e "  ${M}${BOLD}  1${NC}  ${W}Install Proxmox VE${NC}"
    echo -e "     ${DIM}Install Proxmox on bare Debian 12/13${NC}"
    echo
    echo -e "  ${M}${BOLD}  2${NC}  ${W}Setup Proxmox Network${NC}"
    echo -e "     ${DIM}Configure vmbr0 (public) + vmbr1 (private NAT) from scratch${NC}"
    echo
    echo -e "  ${M}${BOLD}  3${NC}  ${W}Install Convoy Panel${NC}"
    echo -e "     ${DIM}Create an LXC and install Convoy Panel on this Proxmox host${NC}"
    echo
    echo -e "  ${M}${BOLD}  4${NC}  ${W}Fix Networking${NC}"
    echo -e "     ${DIM}Diagnose + fix a bridge, validated with a live temp CT test${NC}"
    echo
    echo -e "  ${M}${BOLD}  q${NC}  ${DIM}Quit${NC}"
    echo
    sep
    read -rp "  $(echo -e "${W}Choice${NC} ${DIM}[1/2/3/4/q]${NC}: ")" choice
    echo
    case "$choice" in
      1) [[ $EUID -eq 0 ]] || die "Run as root"; install_proxmox        ;;
      2) [[ $EUID -eq 0 ]] || die "Run as root"; setup_proxmox_network  ;;
      3) [[ $EUID -eq 0 ]] || die "Run as root"; install_convoy         ;;
      4) [[ $EUID -eq 0 ]] || die "Run as root"; fix_networking         ;;
      q|Q|quit|exit)
        echo -e "\n  ${DIM}Made with ♥ by @thatonepotterhead${NC}"
        echo -e "  ${DIM}curl -fsSL https://get.goatdead.com | bash${NC}\n"
        exit 0 ;;
      *) warn "Invalid — enter 1, 2, 3, 4, or q"; sleep 1 ;;
    esac
  done
}

main_menu
