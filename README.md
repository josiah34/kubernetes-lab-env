# Local Kubernetes Lab

This repository provides a quick setup for a local Kubernetes VM environment on your local network, with one control node and two worker nodes managed by Vagrant and VirtualBox.

It is intended for learning, experimenting, and practicing Kubernetes in a repeatable environment on your own computer.

## Environment

The `Vagrantfile` defines three Debian Bookworm virtual machines: one intended control node and two intended worker nodes.

| Machine | Intended role | IP address | CPUs | Memory |
| --- | --- | --- | --- | --- |
| `control-node` | Control plane | `192.168.56.10` | 2 | 2048 MB |
| `node-0` | Worker | `192.168.56.21` | 1 | 2048 MB |
| `node-1` | Worker | `192.168.56.22` | 1 | 2048 MB |

Each VM receives a hostname and entries in `/etc/hosts` for the other machines. VirtualBox names are prefixed with `k8s-`.

The control node has two CPUs and 2048 MB of RAM. Each worker has one CPU and 2048 MB of RAM.

## Networking

The machines use a VirtualBox private network so your host computer and the VMs can communicate using the addresses above. This configuration does not automatically expose the VMs to other devices on your physical local network. Access from those devices requires additional network configuration, such as bridged networking or routing.

If these addresses conflict with an existing network, update both the machine definitions and the `/etc/hosts` provisioning block in `Vagrantfile`.

## Prerequisites

- Vagrant and VirtualBox installed on your computer.
- Hardware virtualization enabled.
- Enough available memory and disk space for all three VMs. The current configuration assigns 6144 MB (6 GiB) of RAM in total, in addition to your host's own requirements.
- Internet access to download the Debian box and any packages installed during provisioning.

## Automated setup

Vagrant runs `scripts/setup.sh` on all three machines after adding their host entries. The script:

- Disables swap for the current session.
- Configures the `overlay` and `br_netfilter` kernel modules to load at boot and loads them immediately.
- Enables IP forwarding and bridge traffic processing through iptables using persistent sysctl settings.
- Installs and starts containerd with systemd cgroups enabled.
- Installs `kubelet`, `kubeadm`, and `kubectl` from the Kubernetes v1.35 package repository and holds those packages against automatic upgrades.
- Sets the kubelet's node IP to the corresponding private-network address and enables the kubelet service.

On `control-node`, the script also initializes the control plane with `kubeadm` when `/etc/kubernetes/admin.conf` does not exist. It uses `192.168.56.10` as the API server's advertised address and `10.244.0.0/16` as the pod network CIDR.

It then copies the administrator kubeconfig to `/home/vagrant/.kube/config` and installs the Calico v3.31.4 operator and custom resources, configuring Calico to use the same pod CIDR.

Worker nodes are prepared by the script but must be joined to the cluster manually.

## Starting the environment

Run these commands from the repository directory:

```sh
vagrant validate
vagrant up --provider=virtualbox
```

The first command checks the Vagrant configuration. The second creates and provisions the VMs; it may take longer on the first run while the base box downloads.

## Joining the worker nodes

After provisioning completes, connect to the control node and generate a join command:

```sh
vagrant ssh control-node
sudo kubeadm token create --print-join-command
```

Copy the printed `kubeadm join` command, then run it with `sudo` on each worker through `vagrant ssh node-0` and `vagrant ssh node-1`. The join command contains credentials for joining the cluster; keep it private.

Once both workers have joined, check the cluster from the control node:

```sh
kubectl get nodes -o wide
kubectl get pods -A
```

The `vagrant` user on the control node can run these commands using the kubeconfig installed by the setup script. Nodes may take some time to become ready while networking starts.

## Connecting to the VMs

Use the machine name to open an SSH session:

```sh
vagrant ssh control-node
vagrant ssh node-0
vagrant ssh node-1
```

Run each command separately to connect to the corresponding VM. Use `exit` to return to your host shell.

## Managing the lab

```sh
# Show the state of all machines
vagrant status

# Stop the VMs while keeping their disks
vagrant halt

# Start existing VMs again
vagrant up

# Re-run provisioning
vagrant provision

# Delete the VMs and their data (prompts for confirmation)
vagrant destroy
```

The current hosts-file provisioner appends entries on each run, so repeated provisioning can create duplicate `/etc/hosts` entries.

The setup script is not fully repeatable yet: it uses `kubectl create` for Calico resources and writes an existing GPG key file without an explicit overwrite option. Re-running provisioning may fail at those steps. Swap is disabled at runtime only; the script does not change `/etc/fstab` to keep it disabled after a reboot. I will mopdify script to handle this in future commits. 

## Repository layout

```text
Vagrantfile       # VM resources, addresses, and provisioning
scripts/setup.sh # Node preparation and control-plane initialization
README.md        # Setup and usage instructions
.gitignore       # Excludes local VM state and credentials
```
