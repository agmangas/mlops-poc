Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  
  config.vm.provider "virtualbox" do |v|
    v.memory = 11980
    v.cpus = 4
  end
  
  config.vm.provision "shell", path: "vagrant-provision.sh"

  config.vm.network "forwarded_port", guest: 30100, host: 30100
  config.vm.network "forwarded_port", guest: 30200, host: 30200
end
