# Local Kubernetes Lab

This repository provides a quick setup for a local Kubernetes VM environment on your local network, with one control node and two worker nodes managed by Vagrant and VirtualBox.

It is intended for learning, experimenting, and practicing Kubernetes in a repeatable environment on your own computer.

## Environment

The `Vagrantfile` defines three Debian Bookworm virtual machines: one intended control node and two intended worker nodes.

| Machine | Intended role | IP address | CPUs | Memory |
| --- | --- | --- | --- | --- |
| `control-node` | Control plane | `192.168.56.10` | 1 | 512 MB |
| `node-0` | Worker | `192.168.56.21` | 1 | 2048 MB |
| `node-1` | Worker | `192.168.56.22` | 1 | 2048 MB |

Each VM receives a hostname and entries in `/etc/hosts` for the other machines. VirtualBox names are prefixed with `k8s-`.

## Networking

The machines use a VirtualBox private network so your host computer and the VMs can communicate using the addresses above. This configuration does not automatically expose the VMs to other devices on your physical local network. Access from those devices requires additional network configuration, such as bridged networking or routing.

If these addresses conflict with an existing network, update both the machine definitions and the `/etc/hosts` provisioning block in `Vagrantfile`.

## Prerequisites

- Vagrant and VirtualBox installed on your computer.
- Hardware virtualization enabled.
- Enough available memory and disk space for all three VMs. The current configuration assigns 4608 MB of RAM in total, in addition to your host's own requirements.
- Internet access to download the Debian box and any packages installed during provisioning.

## Current setup status

This repository currently defines the VM infrastructure for the lab. It does not yet provide a complete, automatically initialized Kubernetes cluster.

The control node runs `scripts/install-tools.sh`, which updates the package index and installs general utilities such as `curl`, `git`, `vim`, `jq`, and network troubleshooting tools. This script does not install Kubernetes.

Installing the Kubernetes components, initializing the control plane, configuring cluster networking, and joining the workers still need to be implemented. Review the VM resource allocations before installing Kubernetes; the control node currently has only 512 MB of RAM and one CPU.

## Starting the environment

Run these commands from the repository directory:

```sh
vagrant validate
vagrant up --provider=virtualbox
```

The first command checks the Vagrant configuration. The second creates and provisions the VMs; it may take longer on the first run while the base box downloads.

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
