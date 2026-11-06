#!/usr/bin/env bash 

set -euo pipefail

# Set noninteractive mode for apt-get so I can run without user input
export DEBIAN_FRONTEND=noninteractive


HOSTNAME=$(hostname)
VAGRANT_HOMEDIR="/home/vagrant"

control_node() {
    if [[ ! -f /etc/kubernetes/admin.conf ]]; then
        kubeadm init \
            --apiserver-advertise-address=192.168.56.10 \
            --pod-network-cidr=10.244.0.0/16 \
            --cri-socket=unix:///run/containerd/containerd.sock
    fi

    export KUBECONFIG=/etc/kubernetes/admin.conf

    install -d -o vagrant -g vagrant -m 0700 "$VAGRANT_HOMEDIR/.kube"

    install -o vagrant -g vagrant -m 0600 \
        /etc/kubernetes/admin.conf \
        "$VAGRANT_HOMEDIR/.kube/config"



    kubectl create -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml

    kubectl create -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml  

    curl -fsSLo calico-custom-resources.yaml \
    https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/custom-resources.yaml

    sed -i \
        's|cidr: 192\.168\.0\.0/16|cidr: 10.244.0.0/16|' \
        calico-custom-resources.yaml

    kubectl apply -f calico-custom-resources.yaml
}

# Disable swap
swapoff -a


# Enable required kernel modules 
sudo tee /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

# Load Kernel Modules
modprobe overlay
modprobe br_netfilter

# Configure Linux networking 
sudo tee /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply configuration 
sysctl --system

if [[ $(sysctl -n net.ipv4.ip_forward) == 1  && $(sysctl -n net.bridge.bridge-nf-call-iptables) == 1 ]]; then
    echo "Successfully configured linux networking"
else
    echo "Failed to configure linux networking"
    exit 1
fi

# Install containerd
apt-get update 
apt-get install -y containerd

if containerd --version; then
    echo "Succesfully installed containerd"
else
    echo "Failed to install containerd"
    exit 1
fi

# Configure containerd 
 mkdir -p /etc/containerd

containerd config default | \
  sudo tee /etc/containerd/config.toml > /dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd
systemctl restart containerd

if [[ $(systemctl is-active containerd) == "active" ]]; then
    echo "Successfully configured containerd"
else
    echo "Failed to configure containerd"
    exit 1
fi


# Install Kubernetes components
apt-get install -y \
    ca-certificates \
    curl \
    gpg

# Create directory for signing keys
mkdir -p -m 755 /etc/apt/keyrings 

# Download and install the kubernetes signing key 
curl -fsSL \
  https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor \
      -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

#Add kubernetes apt repo
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

apt-get update 

# Install kubernetes binaries 

apt-get install -y \
    kubelet \
    kubeadm \
    kubectl 

# Halt automatic updates of kubernetes binaries 
apt-mark hold kubelet kubeadm kubectl 

# Set each node's kubernetes IP 
case "$HOSTNAME" in
    control-node)
        NODE_IP="192.168.56.10"
        ;;
    node-0)
        NODE_IP="192.168.56.21"
        ;;
    node-1)
        NODE_IP="192.168.56.22"
        ;;
    *)
        echo "Unknown hostname: $HOSTNAME" >&2
        exit 1
        ;;
esac

echo "KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP" > /etc/default/kubelet

systemctl enable kubelet
systemctl restart kubelet

if [[ "$HOSTNAME" == "control-node" ]]; then
    control_node
fi

