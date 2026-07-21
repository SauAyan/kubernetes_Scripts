#!/usr/bin/env bash

# Stop immediately if a command fails, an unset variable is used,
# or a command inside a pipeline fails.
set -Eeuo pipefail

# Kubernetes minor-version repository used by this cluster.
KUBERNETES_MINOR="v1.36"

# This script must run as root because it modifies system configuration,
# installs packages, and manages services.
if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run this script with sudo:"
    echo "sudo ./kubernetes_setup.sh"
    exit 1
fi

echo "==> Checking internet connectivity"

curl -4fsS \
    --connect-timeout 15 \
    https://pkgs.k8s.io/ \
    >/dev/null || {
        echo "ERROR: Cannot reach pkgs.k8s.io"
        echo "Check the Azure gateway, route table, NSG and NAT configuration."
        exit 1
    }

echo "==> Cleaning old Kubernetes and CRI-O repository files"

# Remove repository files left by previous or failed installations.
rm -f /etc/apt/sources.list.d/cri-o.list
rm -f /etc/apt/keyrings/cri-o-apt-keyring.gpg
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Complete any interrupted package configuration.
dpkg --configure -a

echo "==> Disabling swap"

# Kubernetes requires swap to be disabled unless explicitly configured otherwise.
swapoff -a

# Disable persistent swap entries in /etc/fstab.
if grep -Eq '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab; then
    sed -ri \
        '/^[^#].*[[:space:]]swap[[:space:]]/s/^/#/' \
        /etc/fstab
fi

echo "==> Loading required kernel modules"

cat > /etc/modules-load.d/kubernetes.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "==> Applying Kubernetes network settings"

cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "==> Configuring APT to use IPv4"

cat > /etc/apt/apt.conf.d/99force-ipv4 <<'EOF'
Acquire::ForceIPv4 "true";
EOF

echo "==> Installing containerd and required packages"

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    containerd \
    apt-transport-https \
    ca-certificates \
    curl \
    gpg

echo "==> Configuring containerd"

mkdir -p /etc/containerd

# Generate a clean default containerd configuration.
containerd config default > /etc/containerd/config.toml

# Use the systemd cgroup driver so it matches kubelet.
sed -i \
    's/SystemdCgroup = false/SystemdCgroup = true/g' \
    /etc/containerd/config.toml

# Ensure the containerd CRI plugin is not disabled.
sed -i \
    's/disabled_plugins = \["cri"\]/disabled_plugins = []/g' \
    /etc/containerd/config.toml

systemctl daemon-reload
systemctl enable --now containerd
systemctl restart containerd

echo "==> Adding Kubernetes ${KUBERNETES_MINOR} repository"

mkdir -p /etc/apt/keyrings

curl -4fsSL \
    "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/Release.key" |
    gpg --dearmor --yes \
        -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat > /etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_MINOR}/deb/ /
EOF

echo "==> Installing kubelet, kubeadm and kubectl"

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    kubelet \
    kubeadm \
    kubectl

# Prevent unintended Kubernetes package upgrades.
apt-mark hold kubelet kubeadm kubectl

# Kubelet may restart until kubeadm init or kubeadm join is completed.
systemctl enable kubelet

echo
echo "========================================"
echo "Installation completed"
echo "========================================"
echo

echo "Installed versions:"
echo "----------------------------------------"

containerd --version
kubeadm version -o short
kubectl version --client
kubelet --version

echo
echo "Validation checks:"
echo "----------------------------------------"

echo -n "Swap: "
if swapon --show | grep -q .; then
    echo "enabled - ERROR"
    swapon --show
    exit 1
else
    echo "disabled"
fi

echo -n "IPv4 forwarding: "
IP_FORWARD="$(sysctl -n net.ipv4.ip_forward)"

if [[ "${IP_FORWARD}" == "1" ]]; then
    echo "1"
else
    echo "${IP_FORWARD} - ERROR"
    exit 1
fi

echo -n "overlay module: "
if lsmod | grep -q '^overlay'; then
    echo "loaded"
else
    echo "not loaded - ERROR"
    exit 1
fi

echo -n "br_netfilter module: "
if lsmod | grep -q '^br_netfilter'; then
    echo "loaded"
else
    echo "not loaded - ERROR"
    exit 1
fi

echo -n "containerd status: "
systemctl is-active containerd

echo -n "containerd enabled: "
systemctl is-enabled containerd

echo -n "kubelet enabled: "
systemctl is-enabled kubelet

echo -n "SystemdCgroup: "
SYSTEMD_CGROUP_LINE="$(
    grep -m1 "SystemdCgroup" /etc/containerd/config.toml || true
)"

if [[ -n "${SYSTEMD_CGROUP_LINE}" ]]; then
    echo "${SYSTEMD_CGROUP_LINE}"
else
    echo "setting not found - ERROR"
    exit 1
fi

echo -n "CRI disabled: "
if grep -Eq \
    '^[[:space:]]*disabled_plugins[[:space:]]*=.*"cri"' \
    /etc/containerd/config.toml; then
    echo "yes - ERROR"
    exit 1
else
    echo "no"
fi

echo
echo "All prerequisite checks completed successfully."
echo
echo "Kubelet may remain inactive or restart repeatedly until"
echo "kubeadm init or kubeadm join is executed."