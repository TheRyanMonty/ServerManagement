# Server Management
HomeLab Server Management Documentation and Build

## Server setup
Complete post VM setup:
* ```curl -sfL https://raw.githubusercontent.com/TheRyanMonty/HomeLab/main/post_vm_build.sh | sh -```

## Ansible Installation
Install ansible and dependencies:
* ```sudo apt install ansible```

Setup the ansible hosts file:
```
sudo echo "[k3s]
pm-k3s-s1 ansible_host=192.168.86.74
pm-k3s-wl1 ansible_host=192.168.86.75
pm-k3s-wl2 ansible_host=192.168.86.78

[homeassistant]
homeassistant ansible_host=192.168.86.39

[servermgmt]
srvmgr ansible_host=192.168.86.53


[all:vars]
ansible_python_interpreter=/usr/bin/python3">>/etc/ansible/hosts
```

Ensure a ssh key is generated for SSH access for user that will be running the ansible jobs:
* ```ssh-keygen```

Obtain the public key (Take note as this will be needed in the following steps):
* ``` cat ~/.ssh/id_rsa.pub```

Add the public key to the authorized_keys file to each host and user you want to run ansible commands as:
* ``` echo "<public_key_from_above>" >> ~/.ssh/authorized_keys```

