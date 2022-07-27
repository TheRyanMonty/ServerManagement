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

Create a yaml playbook for updates:
```
sudo echo "- hosts: servers
  become: true
  become_user: root
  tasks:
    - name: Update apt repo and cache on all Debian/Ubuntu boxes
      apt: update_cache=yes force_apt_get=yes cache_valid_time=3600

    - name: Upgrade all packages on servers
      apt: upgrade=dist force_apt_get=yes

    - name: Check if a reboot is needed on all servers
      register: reboot_required_file
      stat: path=/var/run/reboot-required get_md5=no

    - name: Reboot the box if kernel updated
      reboot:
        msg: "Reboot initiated by Ansible for kernel updates"
        connect_timeout: 5
        reboot_timeout: 300
        pre_reboot_delay: 0
        post_reboot_delay: 30
        test_command: uptime
      when: reboot_required_file.stat.exists" > /etc/ansible/update_ubuntu.yaml
```
