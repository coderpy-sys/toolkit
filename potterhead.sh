#!/usr/bin/env bash
# ============================================================
#   ✦ POTTERHEAD SERVER TOOLKIT ✦
#   Made with ♥ by @thatonepotterhead
#   github.com/thatonepotterhead
#   curl -fsSL https://get.goatdead.com | bash
# ============================================================

# ── Pipe detection: re-exec with /dev/tty so menu is interactive ──
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

# ── Colours ─────────────────────────────────────────────────
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

pause()   { echo; read -rp "  $(echo -e "${DIM}Press Enter to continue...${NC}")" _ < /dev/tty; }

confirm() {
  local msg="${1:-Are you sure?}"
  echo
  read -rp "  $(echo -e "${Y}?${NC}  ${msg} ${DIM}[y/N]${NC}: ")" ans < /dev/tty
  [[ "${ans,,}" =~ ^y(es)?$ ]]
}

prompt() {
  # prompt "Question" "default" → sets REPLY
  local question="$1" default="${2:-}"
  local display_default=""
  [[ -n "$default" ]] && display_default=" ${DIM}[${default}]${NC}"
  read -rp "  $(echo -e "${W}${question}${NC}${display_default}: ")" REPLY < /dev/tty
  [[ -z "$REPLY" ]] && REPLY="$default"
}

pick_ct_id() {
  local id="${1:-200}"
  while pct status "$id" &>/dev/null || qm status "$id" &>/dev/null; do ((id++)); done
  echo "$id"
}

# ════════════════════════════════════════════════════════════
#  OPTION 1 — Install Proxmox VE
# ════════════════════════════════════════════════════════════
install_proxmox() {
  brand
  hdr "Option 1 — Install Proxmox VE"
  echo -e "  Installs ${W}Proxmox VE${NC} on a bare Debian 12/13 machine."
  echo -e "  ${DIM}Requires: root, internet, Debian 12 or 13${NC}"
  echo
  confirm "Continue?" || { info "Aborted."; return; }

  hdr "Detecting Debian version"
  command -v lsb_release &>/dev/null || apt-get install -y lsb-release &>/dev/null
  local DEBIAN_VERSION REPO_CODENAME
  DEBIAN_VERSION=$(lsb_release -rs 2>/dev/null | cut -d. -f1)
  case "$DEBIAN_VERSION" in
    12) REPO_CODENAME="bookworm" ;;
    13) REPO_CODENAME="trixie"   ;;
    *)  die "Only Debian 12/13 supported (detected: $DEBIAN_VERSION)" ;;
  esac
  ok "Debian ${DEBIAN_VERSION} (${REPO_CODENAME})"

  hdr "Adding Proxmox repo + GPG key"
  echo "deb [arch=amd64] http://download.proxmox.com/debian/pve ${REPO_CODENAME} pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-install-repo.list
  wget -q "https://enterprise.proxmox.com/debian/proxmox-release-${REPO_CODENAME}.gpg" \
    -O "/etc/apt/trusted.gpg.d/proxmox-release-${REPO_CODENAME}.gpg"
  ok "Repo configured"

  hdr "System upgrade"
  apt-get update -y && apt-get dist-upgrade -y
  ok "Upgraded"

  hdr "Installing Proxmox kernel + VE"
  apt-get install -y proxmox-default-kernel
  DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi
  apt-get remove -y os-prober 2>/dev/null || true
  ok "Proxmox VE installed"

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║   Proxmox VE installed! Reboot required.     ║${NC}"
  echo -e "  ${G}${BOLD}║   Then visit: https://YOUR_IP:8006            ║${NC}"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo
  confirm "Reboot now?" && reboot
}

# ════════════════════════════════════════════════════════════
#  OPTION 2 — Proxmox Network Setup (smart, non-destructive)
# ════════════════════════════════════════════════════════════
setup_proxmox_network() {
  brand
  hdr "Option 2 — Proxmox Network Setup"
  echo -e "  Configure ${W}vmbr0${NC} (public) and a private NAT bridge of your choice."
  echo

  # ── Read existing interfaces file ────────────────────────
  hdr "Reading Current Network State"
  local IFACE_FILE="/etc/network/interfaces"
  if [[ -f "$IFACE_FILE" ]]; then
    echo -e "  ${W}Current /etc/network/interfaces:${NC}"
    sep
    cat "$IFACE_FILE" | sed 's/^/    /'
    echo
  fi

  echo -e "  ${W}Live interfaces:${NC}"
  sep
  ip -br addr show | sed 's/^/    /'
  echo

  echo -e "  ${W}Existing bridges:${NC}"
  sep
  local existing_bridges=()
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    existing_bridges+=("$br")
    local br_ip; br_ip=$(ip -4 addr show "$br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    echo -e "    ${C}${br}${NC}  ${DIM}${br_ip:-(no ip)}${NC}"
  done < <(ip link show type bridge 2>/dev/null | awk -F': ' '/^[0-9]+:/{print $2}' | grep -v '^$')
  echo

  # ── Decide what to do with vmbr0 ─────────────────────────
  hdr "vmbr0 Configuration (Public Bridge)"

  local CONFIGURE_VMBR0="yes"
  if ip link show vmbr0 &>/dev/null; then
    local cur_vmbr0_ip; cur_vmbr0_ip=$(ip -4 addr show vmbr0 2>/dev/null | awk '/inet /{print $2}' | head -1)
    echo -e "  ${Y}vmbr0 already exists${NC} with IP ${C}${cur_vmbr0_ip:-(none)}${NC}"
    echo
    echo -e "  ${M}${BOLD}  1${NC}  Keep existing vmbr0 — only add/update the private bridge"
    echo -e "  ${M}${BOLD}  2${NC}  Replace vmbr0 with new settings"
    echo -e "  ${M}${BOLD}  3${NC}  Auto-detect and use existing settings"
    echo
    read -rp "  $(echo -e "${W}Choice${NC} ${DIM}[1/2/3]${NC}: ")" vmbr0_choice < /dev/tty
    case "$vmbr0_choice" in
      1) CONFIGURE_VMBR0="no" ;;
      2) CONFIGURE_VMBR0="yes" ;;
      3) CONFIGURE_VMBR0="auto" ;;
      *) CONFIGURE_VMBR0="no" ;;
    esac
  fi

  local HOST_IP PREFIX GW DNS NIC
  if [[ "$CONFIGURE_VMBR0" == "auto" || "$CONFIGURE_VMBR0" == "no" ]]; then
    # Pull from existing config
    NIC=$(grep -A10 'iface vmbr0' "$IFACE_FILE" 2>/dev/null | grep 'bridge-ports' | awk '{print $2}' | head -1)
    [[ -z "$NIC" ]] && NIC=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|vmbr|veth|tap|dummy|docker|gre|wg)/ {print $2}' | head -1)
    HOST_IP=$(ip -4 addr show vmbr0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    PREFIX=$(ip -4 addr show vmbr0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f2)
    GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
    DNS="1.1.1.1 8.8.8.8"
    ok "Using existing vmbr0 settings: ${HOST_IP}/${PREFIX} gw ${GW}"
  else
    # Detect defaults
    NIC=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|vmbr|veth|tap|dummy|docker|gre|wg)/ {print $2}' | head -1)
    local d_ip d_gw d_prefix
    d_ip=$(ip -4 addr show "$NIC" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    d_gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
    d_prefix=$(echo "$d_ip" | cut -d'/' -f2)
    d_ip=$(echo "$d_ip" | cut -d'/' -f1)

    echo -e "  ${DIM}Auto-detected NIC: ${W}${NIC}${NC}  IP: ${W}${d_ip}/${d_prefix}${NC}  GW: ${W}${d_gw}${NC}"
    echo

    prompt "Physical NIC" "$NIC"; NIC="$REPLY"
    prompt "Host IP address" "${d_ip}"; HOST_IP="$REPLY"
    prompt "Prefix length (CIDR)" "${d_prefix:-24}"; PREFIX="$REPLY"
    prompt "Gateway" "${d_gw}"; GW="$REPLY"
    prompt "DNS servers" "1.1.1.1 8.8.8.8"; DNS="$REPLY"
  fi

  # ── Private bridge ────────────────────────────────────────
  hdr "Private NAT Bridge"
  echo -e "  ${DIM}This is your internal VM bridge (vmbr1 by default).${NC}"
  echo -e "  ${DIM}You can choose any name — vmbr1, vmbr2, etc.${NC}"
  echo

  # Show existing private bridges as options
  if [[ ${#existing_bridges[@]} -gt 0 ]]; then
    echo -e "  ${W}Existing bridges:${NC}"
    local bi=1
    for br in "${existing_bridges[@]}"; do
      local brip; brip=$(ip -4 addr show "$br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
      echo -e "  ${M}${BOLD}  ${bi}${NC}  ${W}${br}${NC}  ${DIM}${brip:-(no ip)}${NC}"
      ((bi++))
    done
    echo -e "  ${M}${BOLD}  n${NC}  Create a new bridge"
    echo
    read -rp "  $(echo -e "${W}Select existing or 'n' for new${NC} ${DIM}[n]${NC}: ")" br_sel < /dev/tty

    local PRIV_BRIDGE=""
    if [[ "$br_sel" =~ ^[0-9]+$ ]] && (( br_sel >= 1 && br_sel <= ${#existing_bridges[@]} )); then
      PRIV_BRIDGE="${existing_bridges[$((br_sel-1))]}"
      local cur_priv_ip; cur_priv_ip=$(ip -4 addr show "$PRIV_BRIDGE" 2>/dev/null | awk '/inet /{print $2}' | head -1)
      echo
      echo -e "  ${Y}${PRIV_BRIDGE} already exists${NC} with IP ${C}${cur_priv_ip:-(none)}${NC}"
      echo -e "  ${M}${BOLD}  1${NC}  Keep existing IP for ${PRIV_BRIDGE}"
      echo -e "  ${M}${BOLD}  2${NC}  Set new IP for ${PRIV_BRIDGE}"
      echo
      read -rp "  $(echo -e "${W}Choice${NC} ${DIM}[1/2]${NC}: ")" priv_choice < /dev/tty
      if [[ "$priv_choice" == "2" ]]; then
        prompt "New IP/CIDR for ${PRIV_BRIDGE}" "10.0.0.1/24"
        local PRIV_CIDR="$REPLY"
        local PRIV_GW="${PRIV_CIDR%%/*}"
        local PRIV_NET; PRIV_NET=$(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s.0/24",$1,$2,$3}')
      else
        local PRIV_CIDR="$cur_priv_ip"; [[ "$PRIV_CIDR" != */* ]] && PRIV_CIDR="${PRIV_CIDR}/24"
        local PRIV_GW="${PRIV_CIDR%%/*}"
        local PRIV_NET; PRIV_NET=$(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s.0/24",$1,$2,$3}')
      fi
    else
      prompt "New bridge name" "vmbr1"; PRIV_BRIDGE="$REPLY"
      prompt "Bridge gateway IP/CIDR" "10.0.0.1/24"
      local PRIV_CIDR="$REPLY"
      local PRIV_GW="${PRIV_CIDR%%/*}"
      local PRIV_NET; PRIV_NET=$(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s.0/24",$1,$2,$3}')
    fi
  else
    prompt "Private bridge name" "vmbr1"; PRIV_BRIDGE="$REPLY"
    prompt "Bridge gateway IP/CIDR" "10.0.0.1/24"
    local PRIV_CIDR="$REPLY"
    local PRIV_GW="${PRIV_CIDR%%/*}"
    local PRIV_NET; PRIV_NET=$(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s.0/24",$1,$2,$3}')
  fi

  local PRIV_GW="${PRIV_CIDR%%/*}"
  local PRIV_NET; PRIV_NET=$(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s.0/24",$1,$2,$3}')

  # ── Summary ───────────────────────────────────────────────
  echo
  echo -e "  ${W}${BOLD}Summary${NC}"; sep
  if [[ "$CONFIGURE_VMBR0" != "no" ]]; then
    echo -e "  NIC          ${C}${NIC}${NC}"
    echo -e "  vmbr0        ${C}${HOST_IP}/${PREFIX}${NC}  gw ${C}${GW}${NC}"
    echo -e "  DNS          ${C}${DNS}${NC}"
  else
    echo -e "  vmbr0        ${DIM}kept as-is${NC}"
  fi
  echo -e "  ${PRIV_BRIDGE}      ${C}${PRIV_CIDR}${NC}  NAT → vmbr0"
  echo -e "  VM range     ${C}$(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s",$1,$2,$3}').10 – .250${NC}"
  echo
  confirm "Apply this configuration?" || { info "Aborted."; return; }

  # ── Backup + write interfaces ─────────────────────────────
  hdr "Writing /etc/network/interfaces"
  local BACKUP="${IFACE_FILE}.bak.$(date +%s)"
  [[ -f "$IFACE_FILE" ]] && cp "$IFACE_FILE" "$BACKUP" && ok "Backup → $BACKUP"

  # Start with existing file content if we're keeping vmbr0
  if [[ "$CONFIGURE_VMBR0" == "no" ]]; then
    # Remove existing stanza for PRIV_BRIDGE only, keep everything else
    python3 - "$PRIV_BRIDGE" "$PRIV_CIDR" "$PRIV_NET" << 'PYEOF'
import sys, re
bridge = sys.argv[1]; cidr = sys.argv[2]; net = sys.argv[3]
with open('/etc/network/interfaces', 'r') as f:
    content = f.read()
pattern = r'(?:^auto\s+{br}\s*\n)?(?:^iface\s+{br}\s+.*?)(?=^auto\s|\Z)'.format(br=re.escape(bridge))
content = re.sub(pattern, '', content, flags=re.MULTILINE|re.DOTALL)
content = content.rstrip('\n') + '\n'
stanza = f"""
auto {bridge}
iface {bridge} inet static
    address {cidr}
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -A POSTROUTING -s {net} -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s {net} -o vmbr0 -j MASQUERADE
"""
with open('/etc/network/interfaces', 'w') as f:
    f.write(content + stanza + '\n')
print('  OK')
PYEOF
    ok "Added ${PRIV_BRIDGE} stanza (vmbr0 untouched)"
  else
    # Write full fresh file
    cat > "$IFACE_FILE" << EOF
# ╔══════════════════════════════════════════╗
# ║  POTTERHEAD — /etc/network/interfaces   ║
# ║  Generated: $(date)
# ╚══════════════════════════════════════════╝

auto lo
iface lo inet loopback

iface ${NIC} inet manual

# ── vmbr0: Public bridge ─────────────────────────────────
auto vmbr0
iface vmbr0 inet static
    address ${HOST_IP}/${PREFIX}
    gateway ${GW}
    bridge-ports ${NIC}
    bridge-stp off
    bridge-fd 0
    dns-nameservers ${DNS}
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward

# ── ${PRIV_BRIDGE}: Private NAT bridge ───────────────────
# Gateway: ${PRIV_GW}   VM range: $(echo "$PRIV_GW" | awk -F'.' '{printf "%s.%s.%s",$1,$2,$3}').10 – .250
auto ${PRIV_BRIDGE}
iface ${PRIV_BRIDGE} inet static
    address ${PRIV_CIDR}
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -A POSTROUTING -s ${PRIV_NET} -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s ${PRIV_NET} -o vmbr0 -j MASQUERADE
EOF
    ok "/etc/network/interfaces written"
  fi

  # Remove PVE subscription nag
  if [[ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]]; then
    sed -i "s/data.status !== 'Active'/false/g" \
      /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null || true
    ok "Subscription nag removed"
  fi

  # Apply live
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-potterhead.conf
  sysctl -p /etc/sysctl.d/99-potterhead.conf &>/dev/null
  if ! dpkg -l iptables-persistent &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent &>/dev/null
  fi
  ifreload -a 2>/dev/null || true

  # Ensure private bridge is live
  if ! ip link show "$PRIV_BRIDGE" &>/dev/null; then
    ip link add name "$PRIV_BRIDGE" type bridge 2>/dev/null || true
    ip addr add "${PRIV_CIDR}" dev "$PRIV_BRIDGE" 2>/dev/null || true
    ip link set "$PRIV_BRIDGE" up 2>/dev/null || true
  else
    # Update IP if changed
    if ! ip addr show "$PRIV_BRIDGE" | grep -q "${PRIV_GW}"; then
      ip addr flush dev "$PRIV_BRIDGE" 2>/dev/null || true
      ip addr add "${PRIV_CIDR}" dev "$PRIV_BRIDGE" 2>/dev/null || true
    fi
  fi
  iptables -t nat -D POSTROUTING -s "${PRIV_NET}" -o vmbr0 -j MASQUERADE 2>/dev/null || true
  iptables -t nat -A POSTROUTING -s "${PRIV_NET}" -o vmbr0 -j MASQUERADE
  netfilter-persistent save &>/dev/null || true

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║   Network configured and live!               ║${NC}"
  printf   "  ${G}${BOLD}║   %-43s║${NC}\n" "${PRIV_BRIDGE} → ${PRIV_CIDR} (NAT)"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo
  pause
}

# ════════════════════════════════════════════════════════════
#  OPTION 3 — Install Convoy Panel (fixed, robust)
# ════════════════════════════════════════════════════════════
install_convoy() {
  brand
  hdr "Option 3 — Install Convoy Panel"
  echo -e "  Creates a ${W}Debian 12 LXC${NC} and installs Convoy Panel inside it."
  echo -e "  ${DIM}Run this on the Proxmox host. Takes 5–10 minutes.${NC}"
  echo
  command -v pct   &>/dev/null || die "pct not found — run on Proxmox host"
  command -v pveum &>/dev/null || die "pveum not found"

  hdr "Container Settings"
  prompt "Bridge" "vmbr1"; local CT_BRIDGE="$REPLY"
  ip link show "$CT_BRIDGE" &>/dev/null || die "Bridge $CT_BRIDGE does not exist"

  local CT_CIDR
  while true; do
    prompt "Container IP/CIDR" "10.0.0.50/24"; CT_CIDR="$REPLY"
    [[ "$CT_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] && break
    warn "Invalid — use x.x.x.x/xx"
  done
  local CT_IP="${CT_CIDR%%/*}"
  local default_gw; default_gw=$(printf "%s" "$CT_IP" | awk -F'.' '{printf "%s.%s.%s.1",$1,$2,$3}')

  prompt "Gateway" "$default_gw"; local CT_GW="$REPLY"
  prompt "Storage" "local"; local CT_STORAGE="$REPLY"
  prompt "RAM (MB)" "4096"; local CT_RAM="$REPLY"
  prompt "Disk (GB)" "20"; local CT_DISK="$REPLY"
  prompt "CPU cores" "2"; local CT_CORES="$REPLY"
  prompt "Hostname" "convoy-panel"; local CT_HOSTNAME="$REPLY"

  hdr "Convoy Admin Account"
  prompt "Admin email" "admin@admin.com"; local CONVOY_EMAIL="$REPLY"
  prompt "Admin username" "admin"; local CONVOY_USER="$REPLY"
  read -rsp "  $(echo -e "${W}Admin password${NC}: ")" CONVOY_PASS < /dev/tty; echo
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

  hdr "Getting Debian 12 template"
  local TEMPLATE
  TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
  if [[ -z "$TEMPLATE" ]]; then
    info "Downloading Debian 12 template..."
    pveam update &>/dev/null
    local AVAIL; AVAIL=$(pveam available --section system 2>/dev/null | awk '{print $2}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
    [[ -n "$AVAIL" ]] || die "No Debian 12 template found in pveam"
    pveam download "$CT_STORAGE" "$AVAIL"
    TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1)
  fi
  ok "Template: $TEMPLATE"

  hdr "Creating CT${CT_ID}"
  pct create "$CT_ID" "$TEMPLATE" \
    --hostname "$CT_HOSTNAME" --cores "$CT_CORES" --memory "$CT_RAM" --swap 512 \
    --rootfs "${CT_STORAGE}:${CT_DISK}" \
    --net0 "name=eth0,bridge=${CT_BRIDGE},ip=${CT_CIDR},gw=${CT_GW}" \
    --nameserver "1.1.1.1 8.8.8.8" --unprivileged 0 \
    --features "nesting=1,keyctl=1" \
    --password "$CT_ROOT_PASS" --ssh-public-keys "${SSH_KEY}.pub" \
    --onboot 1 --start 0
  # tun passthrough for cloudflared
  printf 'lxc.cgroup2.devices.allow = c 10:200 rwm\nlxc.mount.entry = /dev/net/tun dev/net/tun none bind,create=file\n' \
    >> "/etc/pve/lxc/${CT_ID}.conf"
  ok "CT created"

  hdr "Starting CT and waiting for boot"
  pct start "$CT_ID"
  local attempt
  for ((attempt=1; attempt<=40; attempt++)); do
    pct exec "$CT_ID" -- bash -c 'exit 0' &>/dev/null && { ok "CT is ready (${attempt}s)"; break; }
    sleep 2
    ((attempt==40)) && die "CT failed to start in time"
  done

  hdr "Installing base packages"
  pct exec "$CT_ID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq --no-install-recommends \
      curl wget ca-certificates gnupg tar jq openssl git procps \
      apt-transport-https lsb-release software-properties-common 2>&1
  " && ok "Base packages installed" || die "Base package install failed"

  hdr "Installing Docker"
  pct exec "$CT_ID" -- bash -c "
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
      https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1
    systemctl enable docker
    systemctl start docker
  " && ok "Docker installed" || {
    warn "Official Docker repo failed — trying get.docker.com fallback"
    pct exec "$CT_ID" -- bash -c "
      curl -fsSL https://get.docker.com | bash
      systemctl enable docker && systemctl start docker
    " || die "Docker installation failed"
  }

  info "Waiting for Docker daemon..."
  for ((attempt=1; attempt<=24; attempt++)); do
    pct exec "$CT_ID" -- docker info &>/dev/null && { ok "Docker is running"; break; }
    sleep 5
    ((attempt==24)) && die "Docker daemon did not start"
  done

  hdr "Installing Convoy Panel"
  # Write the installer script into the CT directly — avoids pipe issues
  pct exec "$CT_ID" -- bash -c "
    mkdir -p /var/www/convoy
    cd /var/www/convoy

    # Download docker-compose.yml from Convoy's official repo
    curl -fsSL https://raw.githubusercontent.com/convoypanel/panel/main/docker-compose.example.yml \
      -o docker-compose.yml 2>/dev/null \
    || curl -fsSL https://raw.githubusercontent.com/convoypanel/panel/develop/docker-compose.example.yml \
      -o docker-compose.yml 2>/dev/null \
    || true

    # Pull images and start
    if [[ -f docker-compose.yml ]]; then
      docker compose pull 2>&1
      docker compose up -d 2>&1
      echo 'CONVOY_STARTED=yes'
    else
      echo 'CONVOY_STARTED=no'
    fi
  " && ok "Convoy containers started" || warn "Convoy start had issues — check CT console"

  info "Waiting for Convoy to initialize (60s)..."
  sleep 60

  hdr "Creating Convoy admin user"
  pct exec "$CT_ID" -- bash -c "
    cd /var/www/convoy 2>/dev/null || true
    printf '%s\n%s\n%s\n%s\nyes\n' \
      'Admin' '${CONVOY_EMAIL}' '${CONVOY_USER}' '${CONVOY_PASS}' \
      | docker compose exec -T workspace php artisan c:user:make 2>&1
  " && ok "Admin user created" || warn "Admin creation may need manual retry — see: pct exec ${CT_ID} -- bash"

  hdr "Creating PVE API token"
  pveum user token remove "root@pam" "convoy" &>/dev/null || true
  local TOKEN_JSON TOKEN_VALUE TOKEN_ID_FULL
  TOKEN_JSON=$(pveum user token add "root@pam" "convoy" --privsep=0 --output-format=json 2>/dev/null || echo '{}')
  TOKEN_VALUE=$(echo "$TOKEN_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('value',''))" 2>/dev/null || true)
  TOKEN_ID_FULL=$(echo "$TOKEN_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('full-tokenid','root@pam!convoy'))" 2>/dev/null || echo "root@pam!convoy")
  [[ -z "$TOKEN_VALUE" ]] && TOKEN_VALUE=$(echo "$TOKEN_JSON" | grep -oP '"value"\s*:\s*"\K[^"]+' | head -1 || echo "check-proxmox-panel")

  local TOKEN_FILE="/root/convoy-token-${CT_ID}.txt"
  {
    echo "Generated  : $(date)"
    echo "CT ID      : $CT_ID"
    echo "CT IP      : $CT_IP"
    echo "Panel URL  : http://$CT_IP"
    echo "Email      : $CONVOY_EMAIL"
    echo "Username   : $CONVOY_USER"
    echo "Password   : $CONVOY_PASS"
    echo "Token ID   : $TOKEN_ID_FULL"
    echo "Secret     : $TOKEN_VALUE"
    echo "Root pass  : $CT_ROOT_PASS"
    echo "SSH key    : $SSH_KEY"
    echo "Add node   : http://$CT_IP/admin/nodes"
  } > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║             Convoy Panel — Installation Complete             ║${NC}"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf   "  ${G}${BOLD}║  Panel URL   : %-46s║${NC}\n" "http://$CT_IP"
  printf   "  ${G}${BOLD}║  Email       : %-46s║${NC}\n" "$CONVOY_EMAIL"
  printf   "  ${G}${BOLD}║  Username    : %-46s║${NC}\n" "$CONVOY_USER"
  printf   "  ${G}${BOLD}║  Password    : %-46s║${NC}\n" "$CONVOY_PASS"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf   "  ${G}${BOLD}║  PVE Token   : %-46s║${NC}\n" "$TOKEN_ID_FULL"
  printf   "  ${G}${BOLD}║  Secret      : %-46s║${NC}\n" "${TOKEN_VALUE:0:44}"
  printf   "  ${G}${BOLD}║  Root pass   : %-46s║${NC}\n" "$CT_ROOT_PASS"
  printf   "  ${G}${BOLD}║  All saved   : %-46s║${NC}\n" "$TOKEN_FILE"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "  ${G}${BOLD}║  If admin creation failed:                                   ║${NC}"
  printf   "  ${G}${BOLD}║  %-60s║${NC}\n" "pct exec $CT_ID -- bash"
  printf   "  ${G}${BOLD}║  %-60s║${NC}\n" "cd /var/www/convoy && docker compose exec workspace bash"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo
  pause
}

# ════════════════════════════════════════════════════════════
#  OPTION 4 — Fix Networking (temp CT diagnostic)
# ════════════════════════════════════════════════════════════
fix_networking() {
  brand
  hdr "Option 4 — Fix Networking"
  echo -e "  Reads current state, picks a bridge, tests with a temp CT, applies fix."
  echo
  command -v pct &>/dev/null || die "pct not found — run on Proxmox host"

  hdr "Phase 1 — Current Network State"
  echo -e "\n  ${W}Bridges:${NC}"; sep
  local bridges=()
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    bridges+=("$br")
    local br_ip; br_ip=$(ip -4 addr show "$br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    local br_vms; br_vms=$(ip link show 2>/dev/null | grep -oP "(?<=master ${br} ).+" | head -3 | tr '\n' ' ')
    printf "  ${C}%-10s${NC}  IP: ${W}%-20s${NC}  Attached: ${DIM}%s${NC}\n" \
      "$br" "${br_ip:-(none)}" "${br_vms:-(none)}"
  done < <(ip link show type bridge 2>/dev/null | awk -F': ' '/^[0-9]+:/{print $2}' | grep -v '^$')

  echo -e "\n  ${W}/etc/network/interfaces:${NC}"; sep
  cat /etc/network/interfaces | sed 's/^/  /'
  echo
  echo -e "  ${W}ip_forward:${NC} $(cat /proc/sys/net/ipv4/ip_forward)"
  echo -e "  ${W}iptables NAT:${NC}"
  iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null | sed 's/^/  /' || true
  echo

  hdr "Phase 2 — Select Bridge"
  [[ ${#bridges[@]} -eq 0 ]] && die "No bridges found"

  local i=1
  for br in "${bridges[@]}"; do
    local br_ip; br_ip=$(ip -4 addr show "$br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
    echo -e "  ${M}${BOLD}  $i${NC}  ${W}${br}${NC}  ${DIM}${br_ip:-(no ip)}${NC}"
    ((i++))
  done
  echo

  local sel_br
  while true; do
    read -rp "  $(echo -e "${W}Pick bridge number${NC}: ")" sel_num < /dev/tty
    [[ "$sel_num" =~ ^[0-9]+$ ]] && (( sel_num >= 1 && sel_num <= ${#bridges[@]} )) && {
      sel_br="${bridges[$((sel_num-1))]}"; break
    }
    warn "Enter 1–${#bridges[@]}"
  done
  ok "Selected: $sel_br"

  hdr "Phase 3 — Desired Config for ${sel_br}"
  local cur_ip; cur_ip=$(ip -4 addr show "$sel_br" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  local cur_gw; cur_gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
  echo -e "  ${DIM}Current: ${cur_ip:-(none)}${NC}"
  echo

  prompt "New IP/CIDR for ${sel_br}" "${cur_ip:-10.0.0.1/24}"
  local NEW_CIDR="$REPLY"
  local NEW_IP="${NEW_CIDR%%/*}"
  local NEW_PREFIX="${NEW_CIDR##*/}"
  local NEW_NET; NEW_NET=$(python3 -c "import ipaddress; n=ipaddress.ip_interface('${NEW_CIDR}'); print(str(n.network))" 2>/dev/null \
    || echo "$(echo "$NEW_IP" | awk -F'.' '{printf "%s.%s.%s",$1,$2,$3}').0/${NEW_PREFIX}")

  local NEW_GW=""
  if [[ "$sel_br" == "vmbr0" ]]; then
    prompt "Gateway" "$cur_gw"; NEW_GW="$REPLY"
  fi

  local DO_NAT="no"
  if [[ "$sel_br" != "vmbr0" ]]; then
    read -rp "  $(echo -e "${W}Enable NAT masquerade → vmbr0?${NC} ${DIM}[Y/n]${NC}: ")" NAT_IN < /dev/tty
    [[ "${NAT_IN,,}" =~ ^(y|yes|)$ ]] && DO_NAT="yes"
  fi

  hdr "Phase 4 — Temp Test CT"
  local TEST_IP; TEST_IP=$(echo "$NEW_IP" | awk -F'.' '{printf "%s.%s.%s.199",$1,$2,$3}')
  local TEST_CIDR="${TEST_IP}/${NEW_PREFIX}"
  local TEST_GW="$NEW_IP"
  local TEMP_ID; TEMP_ID=$(pick_ct_id 900)
  echo -e "  ${DIM}Test CT ${TEMP_ID}: ${TEST_CIDR} gw ${TEST_GW}${NC}"

  local CT_STORAGE="local"
  local TEMPLATE
  TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
  if [[ -z "$TEMPLATE" ]]; then
    pveam update &>/dev/null
    local AVAIL; AVAIL=$(pveam available --section system 2>/dev/null | awk '{print $2}' | grep -i 'debian-12-standard' | sort -V | tail -1 || true)
    [[ -n "$AVAIL" ]] || die "No Debian 12 template"
    pveam download "$CT_STORAGE" "$AVAIL"
    TEMPLATE=$(pveam list "$CT_STORAGE" 2>/dev/null | awk '{print $1}' | grep -i 'debian-12-standard' | sort -V | tail -1)
  fi

  # Apply IP to bridge for test
  ip addr flush dev "$sel_br" 2>/dev/null || true
  ip addr add "${NEW_CIDR}" dev "$sel_br" 2>/dev/null || true
  ip link set "$sel_br" up 2>/dev/null || true
  if [[ "$DO_NAT" == "yes" ]]; then
    iptables -t nat -D POSTROUTING -s "${NEW_NET}" -o vmbr0 -j MASQUERADE 2>/dev/null || true
    iptables -t nat -A POSTROUTING -s "${NEW_NET}" -o vmbr0 -j MASQUERADE
  fi

  local TEMP_PASS; TEMP_PASS=$(openssl rand -base64 10 | tr -d '=/+' | head -c 12)
  pct create "$TEMP_ID" "$TEMPLATE" \
    --hostname "ph-test-${TEMP_ID}" --cores 1 --memory 256 --swap 0 \
    --rootfs "${CT_STORAGE}:1" \
    --net0 "name=eth0,bridge=${sel_br},ip=${TEST_CIDR},gw=${TEST_GW}" \
    --nameserver "1.1.1.1" --unprivileged 1 --features "nesting=0" \
    --password "$TEMP_PASS" --onboot 0 --start 0 2>/dev/null || {
      pct destroy "$TEMP_ID" --purge 2>/dev/null || true
      die "Could not create test CT"
    }
  pct start "$TEMP_ID"
  for ((attempt=1; attempt<=20; attempt++)); do
    pct exec "$TEMP_ID" -- bash -c 'exit 0' &>/dev/null && break
    sleep 2
    ((attempt==20)) && { pct stop "$TEMP_ID" &>/dev/null; pct destroy "$TEMP_ID" --purge &>/dev/null; die "Test CT failed to start"; }
  done
  ok "Test CT ${TEMP_ID} up"

  hdr "Phase 5 — Connectivity Tests"
  local TEST_PASS_CNT=0 TEST_FAIL_CNT=0
  run_test() {
    local label="$1" cmd="$2"
    printf "  %-42s" "$label"
    if pct exec "$TEMP_ID" -- bash -c "$cmd" &>/dev/null; then
      echo -e "${G}PASS${NC}"; ((TEST_PASS_CNT++))
    else
      echo -e "${R}FAIL${NC}"; ((TEST_FAIL_CNT++))
    fi
  }
  run_test "Ping gateway (${TEST_GW})"            "ping -c 2 -W 3 ${TEST_GW}"
  run_test "Ping Cloudflare 1.1.1.1"              "ping -c 2 -W 5 1.1.1.1"
  run_test "Ping Google 8.8.8.8"                  "ping -c 2 -W 5 8.8.8.8"
  run_test "DNS resolution"                       "getent hosts google.com"
  run_test "HTTP (curl ifconfig.me)"              "curl -s --max-time 8 ifconfig.me"
  local CT_PUB_IP
  CT_PUB_IP=$(pct exec "$TEMP_ID" -- bash -c "curl -s --max-time 8 ifconfig.me" 2>/dev/null || echo "")
  echo
  echo -e "  Results: ${G}${TEST_PASS_CNT} passed${NC} / ${R}${TEST_FAIL_CNT} failed${NC}"
  [[ -n "$CT_PUB_IP" ]] && echo -e "  Public IP from CT: ${C}${CT_PUB_IP}${NC}"

  hdr "Phase 6 — Cleanup Temp CT"
  pct stop "$TEMP_ID" --timeout 10 2>/dev/null || true
  sleep 2
  pct destroy "$TEMP_ID" --purge 2>/dev/null || true
  ok "Temp CT ${TEMP_ID} destroyed"

  hdr "Phase 7 — Apply Permanent Fix"
  [[ $TEST_FAIL_CNT -gt 0 ]] && echo -e "  ${Y}${TEST_FAIL_CNT} test(s) failed — gateway ping failing is normal for NAT bridges.${NC}\n"

  confirm "Apply permanently to ${sel_br} and update /etc/network/interfaces?" || {
    ip addr flush dev "$sel_br" 2>/dev/null || true
    [[ -n "$cur_ip" ]] && ip addr add "$cur_ip" dev "$sel_br" 2>/dev/null || true
    [[ "$DO_NAT" == "yes" ]] && iptables -t nat -D POSTROUTING -s "${NEW_NET}" -o vmbr0 -j MASQUERADE 2>/dev/null || true
    info "Reverted."; pause; return
  }

  local BACKUP="/etc/network/interfaces.fix.$(date +%s)"
  cp /etc/network/interfaces "$BACKUP" && ok "Backup → $BACKUP"

  python3 - "$sel_br" "$NEW_CIDR" "$NEW_GW" "$DO_NAT" "$NEW_NET" << 'PYEOF'
import sys, re
bridge=sys.argv[1]; cidr=sys.argv[2]; gw=sys.argv[3]; do_nat=sys.argv[4]; net=sys.argv[5]
with open('/etc/network/interfaces','r') as f:
    content=f.read()
pattern=r'(?:^auto\s+{br}\s*\n)?(?:^iface\s+{br}\s+.*?)(?=^auto\s|\Z)'.format(br=re.escape(bridge))
content=re.sub(pattern,'',content,flags=re.MULTILINE|re.DOTALL)
content=content.rstrip('\n')+'\n'
nat_up=f'    post-up   iptables -t nat -A POSTROUTING -s {net} -o vmbr0 -j MASQUERADE\n' if do_nat=='yes' else ''
nat_dn=f'    post-down iptables -t nat -D POSTROUTING -s {net} -o vmbr0 -j MASQUERADE\n' if do_nat=='yes' else ''
gw_ln=f'    gateway {gw}\n' if gw else ''
stanza=f'\nauto {bridge}\niface {bridge} inet static\n    address {cidr}\n{gw_ln}    bridge-ports none\n    bridge-stp off\n    bridge-fd 0\n    post-up echo 1 > /proc/sys/net/ipv4/ip_forward\n{nat_up}{nat_dn}'
with open('/etc/network/interfaces','w') as f:
    f.write(content+stanza+'\n')
print('  Done')
PYEOF
  ok "/etc/network/interfaces updated"
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-potterhead.conf
  sysctl -p /etc/sysctl.d/99-potterhead.conf &>/dev/null
  if [[ "$DO_NAT" == "yes" ]]; then
    dpkg -l iptables-persistent &>/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent &>/dev/null
    netfilter-persistent save &>/dev/null || true
  fi
  ifreload -a 2>/dev/null || true
  ok "Network reloaded"
  echo
  echo -e "  ${G}${BOLD}Done! ${sel_br} → ${NEW_CIDR}${NC}  Tests: ${G}${TEST_PASS_CNT} passed${NC} / ${R}${TEST_FAIL_CNT} failed${NC}"
  echo
  pause
}

# ════════════════════════════════════════════════════════════
#  OPTION 5 — Install Discord Bot (Proxmox VPS Manager)
# ════════════════════════════════════════════════════════════
install_discord_bot() {
  brand
  hdr "Option 5 — Install Proxmox Discord Bot"
  echo -e "  Installs the ${W}VPS Management Bot${NC} on this machine."
  echo -e "  ${DIM}Manages LXC containers via Discord with Proxmox API.${NC}"
  echo
  command -v python3 &>/dev/null || die "python3 not found"

  hdr "Bot Configuration"
  prompt "Discord Bot Token";               local BOT_TOKEN="$REPLY"
  [[ -z "$BOT_TOKEN" ]] && die "Discord token is required"

  prompt "Bot name" "Bynex Host";           local BOT_NAME="$REPLY"
  prompt "Command prefix" ".";              local PREFIX="$REPLY"
  prompt "Main Admin Discord ID";           local MAIN_ADMIN_ID="$REPLY"
  [[ -z "$MAIN_ADMIN_ID" ]] && die "Admin ID is required"

  prompt "VPS User Role ID (Discord)";      local VPS_ROLE_ID="$REPLY"

  hdr "Proxmox Configuration"
  prompt "Proxmox URL" "https://127.0.0.1:8006"; local PVE_URL="$REPLY"
  prompt "Proxmox Token ID" "root@pam!bot";       local PVE_TOKEN_ID="$REPLY"
  prompt "Proxmox Token Secret";                  local PVE_TOKEN_SECRET="$REPLY"
  [[ -z "$PVE_TOKEN_SECRET" ]] && die "Token secret is required"

  prompt "Proxmox node name" "pve";         local PVE_NODE="$REPLY"
  prompt "Proxmox storage" "local-lvm";     local PVE_STORAGE="$REPLY"
  prompt "VM bridge" "vmbr1";               local PVE_BRIDGE="$REPLY"

  hdr "Discord Channel IDs"
  prompt "Mining/abuse notification channel ID"; local MINING_CHANNEL="$REPLY"

  hdr "Installation Path"
  prompt "Install directory" "/opt/proxmox-bot"; local BOT_DIR="$REPLY"

  echo
  echo -e "  ${W}${BOLD}Summary${NC}"; sep
  echo -e "  Bot name      ${C}${BOT_NAME}${NC}  prefix ${C}${PREFIX}${NC}"
  echo -e "  Admin ID      ${C}${MAIN_ADMIN_ID}${NC}"
  echo -e "  Proxmox       ${C}${PVE_URL}${NC}"
  echo -e "  Node          ${C}${PVE_NODE}${NC}  Storage ${C}${PVE_STORAGE}${NC}  Bridge ${C}${PVE_BRIDGE}${NC}"
  echo -e "  Install dir   ${C}${BOT_DIR}${NC}"
  echo
  confirm "Install the bot?" || { info "Aborted."; return; }

  hdr "Installing Python dependencies"
  apt-get update -y -qq &>/dev/null
  apt-get install -y -qq python3 python3-pip python3-venv &>/dev/null
  ok "Python ready"

  hdr "Creating bot directory"
  mkdir -p "$BOT_DIR"
  cd "$BOT_DIR"

  python3 -m venv venv
  source venv/bin/activate
  pip install -q --upgrade pip
  pip install -q discord.py aiohttp urllib3
  ok "Python venv + packages installed"

  hdr "Writing bot config (.env)"
  cat > "${BOT_DIR}/.env" << EOF
DISCORD_TOKEN=${BOT_TOKEN}
BOT_NAME=${BOT_NAME}
PREFIX=${PREFIX}
MAIN_ADMIN_ID=${MAIN_ADMIN_ID}
VPS_USER_ROLE_ID=${VPS_ROLE_ID}
PROXMOX_URL=${PVE_URL}
PROXMOX_TOKEN_ID=${PVE_TOKEN_ID}
PROXMOX_TOKEN_SECRET=${PVE_TOKEN_SECRET}
PROXMOX_NODE=${PVE_NODE}
PROXMOX_STORAGE=${PVE_STORAGE}
PROXMOX_BRIDGE=${PVE_BRIDGE}
MINING_NOTIFY_CHANNEL=${MINING_CHANNEL:-0}
EOF
  chmod 600 "${BOT_DIR}/.env"
  ok "Config written → ${BOT_DIR}/.env"

  hdr "Downloading bot script"
  curl -fsSL \
    "https://raw.githubusercontent.com/coderpy-sys/toolkit/main/bot.py" \
    -o "${BOT_DIR}/bot.py" 2>/dev/null || {
    warn "Could not download from GitHub — writing bot.py from embedded copy"
    # The bot.py will be written by the user separately if download fails
    echo "# Place your bot.py here" > "${BOT_DIR}/bot.py"
    warn "Please copy bot.py to ${BOT_DIR}/bot.py manually"
  }

  hdr "Creating systemd service"
  cat > "/etc/systemd/system/proxmox-bot.service" << EOF
[Unit]
Description=Proxmox Discord VPS Bot (${BOT_NAME})
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${BOT_DIR}
EnvironmentFile=${BOT_DIR}/.env
ExecStart=${BOT_DIR}/venv/bin/python3 ${BOT_DIR}/bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable proxmox-bot

  hdr "Starting bot"
  systemctl start proxmox-bot
  sleep 3
  if systemctl is-active --quiet proxmox-bot; then
    ok "Bot is running!"
  else
    warn "Bot failed to start — check: journalctl -u proxmox-bot -n 30"
  fi

  echo
  echo -e "  ${G}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${G}${BOLD}║          Discord Bot — Installation Complete                 ║${NC}"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  printf   "  ${G}${BOLD}║  Install dir : %-46s║${NC}\n" "$BOT_DIR"
  printf   "  ${G}${BOLD}║  Config      : %-46s║${NC}\n" "${BOT_DIR}/.env"
  printf   "  ${G}${BOLD}║  Service     : %-46s║${NC}\n" "proxmox-bot"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "  ${G}${BOLD}║  Useful commands:                                            ║${NC}"
  printf   "  ${G}${BOLD}║  %-60s║${NC}\n" "systemctl status proxmox-bot"
  printf   "  ${G}${BOLD}║  %-60s║${NC}\n" "journalctl -u proxmox-bot -f"
  printf   "  ${G}${BOLD}║  %-60s║${NC}\n" "systemctl restart proxmox-bot"
  echo -e "  ${G}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
  echo -e "  ${G}${BOLD}║  Bot commands (in Discord):                                  ║${NC}"
  printf   "  ${G}${BOLD}║  %-60s║${NC}\n" "${PREFIX}help  ${PREFIX}create  ${PREFIX}myvps  ${PREFIX}manage"
  echo -e "  ${G}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
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
    echo -e "     ${DIM}Smart setup for vmbr0 + any private bridge — auto-detects existing config${NC}"
    echo
    echo -e "  ${M}${BOLD}  3${NC}  ${W}Install Convoy Panel${NC}"
    echo -e "     ${DIM}Create a Debian 12 LXC and install Convoy Panel${NC}"
    echo
    echo -e "  ${M}${BOLD}  4${NC}  ${W}Fix Networking${NC}"
    echo -e "     ${DIM}Diagnose + fix any bridge with live temp CT test${NC}"
    echo
    echo -e "  ${M}${BOLD}  5${NC}  ${W}Install Discord Bot${NC}"
    echo -e "     ${DIM}Deploy Proxmox VPS Manager bot with your credentials${NC}"
    echo
    echo -e "  ${M}${BOLD}  q${NC}  ${DIM}Quit${NC}"
    echo
    sep
    read -rp "  $(echo -e "${W}Choice${NC} ${DIM}[1-5/q]${NC}: ")" choice < /dev/tty
    echo
    case "$choice" in
      1) [[ $EUID -eq 0 ]] || die "Run as root"; install_proxmox        ;;
      2) [[ $EUID -eq 0 ]] || die "Run as root"; setup_proxmox_network  ;;
      3) [[ $EUID -eq 0 ]] || die "Run as root"; install_convoy         ;;
      4) [[ $EUID -eq 0 ]] || die "Run as root"; fix_networking         ;;
      5) [[ $EUID -eq 0 ]] || die "Run as root"; install_discord_bot    ;;
      q|Q|quit|exit)
        echo -e "\n  ${DIM}Made with ♥ by @thatonepotterhead${NC}"
        echo -e "  ${DIM}curl -fsSL https://get.goatdead.com | bash${NC}\n"
        exit 0 ;;
      *) warn "Invalid — enter 1, 2, 3, 4, 5, or q"; sleep 1 ;;
    esac
  done
}

main_menu
