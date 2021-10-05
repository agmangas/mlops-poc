$prov = <<-SCRIPT
set -ex
snap install microk8s --classic --channel=1.21
usermod -a -G microk8s vagrant
microk8s status --wait-ready
microk8s enable dns storage ingress helm3 dashboard
apt-get update -y && apt-get install -y python3 python-is-python3
echo -e '#!/bin/sh\nmicrok8s kubectl "$@"' >> /usr/bin/kubectl
chmod 755 /usr/bin/kubectl
kubectl version
echo -e '#!/bin/sh\nmicrok8s helm3 "$@"' >> /usr/bin/helm
chmod 755 /usr/bin/helm
helm version
SCRIPT

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  
  config.vm.provider "virtualbox" do |v|
    v.memory = 10240
    v.cpus = 4
  end
  
  config.vm.provision "shell", inline: $prov

  config.vm.network "forwarded_port", guest: 30100, host: 30100
  config.vm.network "forwarded_port", guest: 30200, host: 30200
end
