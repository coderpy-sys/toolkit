# Stop VMs
for id in $(qm list | awk 'NR>1{print $1}'); do
    qm stop $id --skiplock 2>/dev/null || true
done

# Destroy VMs
for id in $(qm list | awk 'NR>1{print $1}'); do
    qm destroy $id --destroy-unreferenced-disks 1 --purge 1
done

# Stop LXCs
for id in $(pct list | awk 'NR>1{print $1}'); do
    pct stop $id 2>/dev/null || true
done

# Destroy LXCs
for id in $(pct list |awk 'NR>1{print $1}'); do
    pct destroy $id --purge
done

apt update

apt install --reinstall \
proxmox-ve \
pve-manager \
pve-cluster \
qemu-server \
lxc-pve \
ifupdown2 \
pve-firewall \
novnc-pve \
libpve-http-server-perl \
libpve-access-control \
proxmox-widget-toolkit \
-y
