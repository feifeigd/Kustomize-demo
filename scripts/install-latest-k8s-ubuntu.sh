#!/usr/bin/env bash
set -euo pipefail

# Install the latest stable Kubernetes packages on Ubuntu.
# This script removes old kubeadm/kubelet/kubectl packages first.
#
# Defaults:
#   - installs containerd
#   - installs kubeadm, kubelet, kubectl from pkgs.k8s.io
#   - initializes a single control-plane node with kubeadm
#   - installs flannel after kubeadm init
#
# Examples:
#   sudo bash scripts/install-latest-k8s-ubuntu.sh
#   AUTO_YES=true sudo -E bash scripts/install-latest-k8s-ubuntu.sh
#   INIT_CLUSTER=false sudo -E bash scripts/install-latest-k8s-ubuntu.sh

AUTO_YES="${AUTO_YES:-false}"
INIT_CLUSTER="${INIT_CLUSTER:-true}"
INSTALL_FLANNEL="${INSTALL_FLANNEL:-true}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
K8S_STABLE_URL="${K8S_STABLE_URL:-https://dl.k8s.io/release/stable.txt}"
FLANNEL_MANIFEST_URL="${FLANNEL_MANIFEST_URL:-https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root, for example: sudo bash $0" >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "/etc/os-release was not found; this script is intended for Ubuntu." >&2
  exit 1
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script is intended for Ubuntu. Detected ID=${ID:-unknown}." >&2
  exit 1
fi

confirm() {
  local message="$1"

  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi

  read -r -p "${message} Type 'yes' to continue: " answer
  [[ "${answer}" == "yes" ]]
}

run_if_exists() {
  local cmd="$1"
  shift

  if command -v "${cmd}" >/dev/null 2>&1; then
    "${cmd}" "$@"
  fi
}

echo "Ubuntu version: ${PRETTY_NAME:-unknown}"
echo "This will uninstall existing Kubernetes packages before installing the latest stable release."

if ! confirm "Continue?"; then
  echo "Canceled."
  exit 0
fi

echo "Disabling swap..."
swapoff -a || true
if [[ -f /etc/fstab ]]; then
  cp /etc/fstab "/etc/fstab.k8s-backup.$(date +%Y%m%d%H%M%S)"
  sed -i.bak -E '/[[:space:]]swap[[:space:]]/ s/^/# disabled by install-latest-k8s-ubuntu.sh /' /etc/fstab
fi

echo "Resetting existing kubeadm state if kubeadm is present..."
if command -v kubeadm >/dev/null 2>&1; then
  kubeadm reset -f || true
fi

echo "Uninstalling old Kubernetes packages..."
apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
apt-get remove -y kubelet kubeadm kubectl kubernetes-cni cri-tools 2>/dev/null || true
apt-get purge -y kubelet kubeadm kubectl kubernetes-cni cri-tools 2>/dev/null || true
apt-get autoremove -y

echo "Removing old Kubernetes cluster state and CNI config..."
rm -rf /etc/kubernetes
rm -rf /var/lib/etcd
rm -rf /var/lib/kubelet
rm -rf /etc/cni/net.d
rm -rf /opt/cni/bin/flannel
rm -f /run/flannel/subnet.env

echo "Removing old Kubernetes apt sources..."
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -f /etc/apt/sources.list.d/kubernetes.list.save
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg

echo "Installing base dependencies..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg

echo "Installing and configuring containerd..."
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd

echo "Loading kernel modules and sysctl settings..."
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

echo "Resolving latest stable Kubernetes version..."
stable_version="$(curl -fsSL "${K8S_STABLE_URL}")"
k8s_minor="$(echo "${stable_version}" | sed -E 's/^v([0-9]+\.[0-9]+)\..*$/v\1/')"

if [[ -z "${k8s_minor}" || "${k8s_minor}" == "${stable_version}" ]]; then
  echo "Failed to derive Kubernetes minor version from ${stable_version}" >&2
  exit 1
fi

echo "Latest stable Kubernetes: ${stable_version}"
echo "Using package repository: ${k8s_minor}"

echo "Adding Kubernetes apt repository..."
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${k8s_minor}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat >/etc/apt/sources.list.d/kubernetes.list <<EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${k8s_minor}/deb/ /
EOF

echo "Installing kubelet, kubeadm and kubectl..."
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "Installed versions:"
kubeadm version
kubectl version --client=true
kubelet --version

if [[ "${INIT_CLUSTER}" == "true" ]]; then
  echo "Initializing Kubernetes control plane with pod CIDR ${POD_CIDR}..."
  kubeadm init --pod-network-cidr="${POD_CIDR}"

  target_user="${SUDO_USER:-root}"
  if [[ "${target_user}" != "root" ]]; then
    target_home="$(getent passwd "${target_user}" | cut -d: -f6)"
    mkdir -p "${target_home}/.kube"
    cp -f /etc/kubernetes/admin.conf "${target_home}/.kube/config"
    chown "${target_user}:${target_user}" "${target_home}/.kube/config"
    export KUBECONFIG=/etc/kubernetes/admin.conf
  else
    mkdir -p /root/.kube
    cp -f /etc/kubernetes/admin.conf /root/.kube/config
    export KUBECONFIG=/etc/kubernetes/admin.conf
  fi

  if [[ "${INSTALL_FLANNEL}" == "true" ]]; then
    echo "Installing flannel..."
    kubectl apply -f "${FLANNEL_MANIFEST_URL}"
    kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=180s
  fi

  echo "Allowing workloads on this single control-plane node..."
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
fi

echo
echo "Kubernetes installation completed."
echo "Useful checks:"
echo "  kubectl get nodes -o wide"
echo "  kubectl get pods -A -o wide"
