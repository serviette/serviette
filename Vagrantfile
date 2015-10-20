# -*- mode: ruby -*-
# vi: set ft=ruby :

require "fileutils"

# the following is adapted from https://gist.github.com/juanje/3797297
def local_cache(basebox_name)
	cache_dir = Vagrant::Environment.new.home_path.join('cache', 'apt', basebox_name)
	partial_dir = cache_dir.join('partial')
	FileUtils.makedirs(partial_dir) unless partial_dir.exist?
	cache_dir
end

VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "debian/jessie64"
  config.vm.network "private_network", type: "dhcp"
  config.vm.synced_folder "../serviette", "/serviette"
  cache_dir = local_cache(config.vm.box)
  config.vm.synced_folder cache_dir, "/var/cache/apt/archives/"

  # workaround for "not a stdin"
  # https://github.com/mitchellh/vagrant/issues/1673
  config.ssh.shell = "bash -c 'BASH_ENV=/etc/profile exec bash'"

  # do the serviette install in the provisioning phase
  config.vm.provision :shell, inline: "/bin/bash /serviette/serviette.sh"
end
