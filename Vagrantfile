
# -*- mode: ruby -*-
# vi: set ft=ruby :

MACHINES = [
  { name: "control-node", ip: "192.168.56.10", cpu: 1, ram: 512 },
  { name: "node-0",  ip: "192.168.56.21", cpu: 1, ram: 2048 },
  { name: "node-1",  ip: "192.168.56.22", cpu: 1, ram: 2048 }
]

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"

  MACHINES.each do |node|
    config.vm.define node[:name] do |vm|
      vm.vm.hostname = node[:name]

      vm.vm.network "private_network", ip: node[:ip]

      vm.vm.provider "virtualbox" do |vb|
        vb.name = "k8s-#{node[:name]}"
        vb.cpus = node[:cpu]
        vb.memory = node[:ram]
      end

      if node[:name] == "control-node"
        vm.vm.provision "shell",
            path: "scripts/install-tools.sh"
      end

      vm.vm.provision "shell", inline: <<-SHELL
        cat >> /etc/hosts <<EOF
192.168.56.10 control-node
192.168.56.21 node-0
192.168.56.22 node-1
EOF
      SHELL
    end
  end
end
