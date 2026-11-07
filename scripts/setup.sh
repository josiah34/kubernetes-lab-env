#!/usr/bin/env bash
# This is a simple script which provisions all the necessary configurations to bootstrap a kubernetes cluster using kubeadm with one control node
# and two worker nodes. This script should be run as root.
set -euo pipefail

# Set noninteractive mode for apt-get so I can run without user input
export DEBIAN_FRONTEND=noninteractive


HOSTNAME=$(hostname)
VAGRANT_HOMEDIR="/home/vagrant"

########################################## HELPER FUNCTIONS ##########################################
log() {
    local level="$1"
    shift

    printf '[%s] [%s] %s\n' \
        "$(date -Is)" \
        "$level" \
        "$*"
}

wait_for_apiserver() {
    log INFO "Waiting for Kubernetes API server"

    for attempt in {1..30}; do
        if kubectl --kubeconfig=/etc/kubernetes/admin.conf \
            get --raw=/readyz >/dev/null 2>&1; then
            log INFO "API server ready"
            return 0
        fi

        sleep 5
    done

    log ERROR "API server did not become ready"
    return 1
}

control_node() {
    if [[ ! -f /etc/kubernetes/admin.conf ]]; then
        kubeadm init \
            --apiserver-advertise-address=192.168.56.10 \
            --pod-network-cidr=10.244.0.0/16 \
            --cri-socket=unix:///run/containerd/containerd.sock
    fi

    wait_for_apiserver

    export KUBECONFIG=/etc/kubernetes/admin.conf

    install -d -o vagrant -g vagrant -m 0700 "$VAGRANT_HOMEDIR/.kube"

    install -o vagrant -g vagrant -m 0600 \
        /etc/kubernetes/admin.conf \
        "$VAGRANT_HOMEDIR/.kube/config"



    kubectl apply --server-side -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml

    kubectl wait \
        --for=condition=Established \
        crd/installations.operator.tigera.io \
        --timeout=120s

    kubectl apply -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml

    kubectl rollout status \
        deployment/tigera-operator \
        -n tigera-operator \
        --timeout=180s

    curl -fsSLo calico-custom-resources.yaml \
    https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/custom-resources.yaml

    sed -i \
        's|cidr: 192\.168\.0\.0/16|cidr: 10.244.0.0/16|' \
        calico-custom-resources.yaml

    kubectl apply -f calico-custom-resources.yaml


    kubeadm token create --print-join-command > /vagrant/join-command.sh
}


worker_node() {


    if [[ ! -f /etc/kubernetes/kubelet.conf ]]; then
        log INFO "Joining kubernetes cluster"
        if [[ ! -s /vagrant/join-command.sh ]]; then
            log ERROR "Join command not found"
             return 1
        else
            bash /vagrant/join-command.sh
        fi
    else
        log INFO "Worker already joined, skipping join command"
        return 0
    fi
}

configure_containerd() {
    local config="/etc/containerd/config.toml"

    log INFO "Configuring containerd"

    mkdir -p /etc/containerd

    # Generate the default configuration
    containerd config default > "$config"

    # Enable systemd cgroups
    sed -i \
        's/SystemdCgroup = false/SystemdCgroup = true/' \
        "$config"

    # Restart containerd to apply configuration
    systemctl enable containerd
    systemctl restart containerd

    # Verify service is running
    if ! systemctl is-active --quiet containerd; then
        log ERROR "Containerd is not active"
        return 1
    fi

    # Verify cgroup configuration
    if ! containerd config dump | grep -Eq 'SystemdCgroup = true'; then
        log ERROR "Containerd systemd cgroups not enabled"
        return 1
    fi

    log INFO "Containerd configured with systemd cgroups"
}
######################################################################################################

if (( EUID != 0 )); then
    log ERROR "This script must be run as root"
    exit 1
fi

# Disable swap
swapoff -a


# Enable required kernel modules
tee /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

# Load Kernel Modules
modprobe overlay
modprobe br_netfilter

# Configure Linux networking
tee /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply configuration
sysctl --system

if [[ $(sysctl -n net.ipv4.ip_forward) == 1  && $(sysctl -n net.bridge.bridge-nf-call-iptables) == 1 ]]; then
    log INFO "Successfully configured linux networking"
else
    log ERROR "Failed to configure linux networking"
    exit 1
fi

# Install containerd
apt-get update
apt-get install -y containerd

# Configure containerd
configure_containerd

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
        log ERROR "Unknown hostname: $HOSTNAME"
        exit 1
        ;;
esac

echo "KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP" > /etc/default/kubelet

systemctl enable kubelet
systemctl restart kubelet

if [[ "$HOSTNAME" == "control-node" ]]; then
    control_node
else
    worker_node
fi


log INFO "Setup complete"
