# Server Management
HomeLab Server Management Documentation and Build

## Introduction
The purpose of this repo is, selfishly, to document the setup and configuration I have outside of my network as a reference point in the future. Unselfishly I hope putting this in a public space will help others who are attempting to do a similar setup (high level defined below) be able to do so in a way that's easier than my learning epxerience and to have as a reference point of a working configuration.

### Goals of the configuration:
1. To ease server maintenance activities via automation
2. To monitor logs, kubernetes, web services, etc. and take action (notification, trigger automated healing, etc.) as needed.

### What's doing the work:
- ansible = Server automation management toolset
- prometheus = Server and service monitoring tool


### Good routine questions:
1. Is everything that needs to be backed up, backed up or have a data replication strategy (i.e. customized config files)?
2. Are passwords reasonable?
3. Are appropriate logs being monitored?


## Server setup
Complete post VM setup:
* ```curl -sfL https://raw.githubusercontent.com/TheRyanMonty/HomeLab/main/post_vm_build.sh | sh -```



### Ansible Installation
Install ansible and dependencies:
* ```sudo apt install ansible```

Setup the ansible directories and pull down host files and playbooks:
```
#Create playbooks and inventories directories
mkdir -p /etc/ansible/playbooks
mkdir -p /etc/ansible/inventories
#Grab needed inventory files
cd /etc/ansible/playbooks
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Playbooks/build_server_k3s_server.yaml
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Playbooks/build_server_post_creation.yaml
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Playbooks/update_all.yaml
#Grab inventoires
cd /etc/ansible/inventories
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Inventories/homeassist
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Inventories/hosts
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Inventories/k3s_servers
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Inventories/new_server
wget https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/main/Ansible%20Inventories/servermgmt
```

Ensure a ssh key is generated for SSH access for user that will be running the ansible jobs:
* ```ssh-keygen```

Obtain the public key (Take note as this will be needed in the following steps):
* ``` cat ~/.ssh/id_rsa.pub```

Add the public key to the authorized_keys file to each host and user you want to run ansible commands as:
* ``` echo "<public_key_from_above>" >> ~/.ssh/authorized_keys```

Test the playbook:
* ``` /usr/bin/ansible-playbook -i /etc/ansible/inventories/homeassist /etc/ansible/playbooks/update_all.yaml -u root ```

#### Ansible Scheduling
Edit cron for the user setup to run ansible:
* ```crontab -e```

Paste the following for midnight on saturday morning (server management) sunday morning (for everything else):
```
##
##
## Ansible package updates for servers - list servers via cat /etc/ansible/hosts
0 0 * * 0 /usr/bin/ansible-playbook -i /etc/ansible/inventories/k3s_servers /etc/ansible/playbooks/update_all.yaml -u root
0 0 * * 0 /usr/bin/ansible-playbook -i /etc/ansible/inventories/homeassist /etc/ansible/playbooks/update_all.yaml -u root
0 0 * * 6 /usr/bin/ansible-playbook -i /etc/ansible/inventories/servermgmt /etc/ansible/playbooks/update_all.yaml -u root
```

### Create logging location owned by ansible user
* NOTE: /etc/ansible/ansible.cfg contains log file location
```
sudo mkdir /var/log/ansible/
sudo chown monty /var/log/ansible
sudo chmod 775 /var/log/ansible
```


### Prometheus Installation
```
docker run --detach \
    --name my-prometheus \
    --publish 9090:9090 \
    --volume prometheus-volume:/prometheus \
    --volume /etc/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus
```
### Install Certbot and download wildcard certs for deployment on internal servers
* Install Certbot
```
sudo apt install certbot
```
* Register for certificate
```
sudo certbot certonly --manual \
  --preferred-challenges=dns \
  --email ryan.g.montgomery@gmail.com \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --manual-public-ip-logging-ok \
  -d "*.montysplace.org"
```
* Need to determine best way to automate and make accessible for sites

## DNS Setup
DNS is setup as of this writing on a seperate VM for testing
* Install bind9 and dnsutils
```
sudo apt install bind9 dnsutils
```

* Set dns server as primary and primary/reverse zones
```
sudo echo "zone \"montysplace.local\" {
    type master;
    file \"/etc/bind/db.montysplace.local\";
};

zone \"1.50.10.in-addr.arpa\" {
    type master;
    file \"/etc/bind/db.10.50.1\";
};

zone \"10.50.10.in-addr.arpa\" {
    type master;
    file \"/etc/bind/db.10.50.10\";
};" >> /etc/bind/named.conf.local
```
* Disable ipv6 to prevent constant ipv6 related errors
```
sudo systemctl edit bind9
```
* Insert this between the first and second block of comments
```
[Service]
ExecStart=
ExecStart=/usr/sbin/named -4 -f $OPTIONS
```

* Pull down DB files
My current 3 db files (db.montysplace.local db.10.50.1 and db.10.50.10) and named.conf.options are backed up on my NAS under server backups\dns, they go in /etc/bind/

* Restart bind
```
sudo systemctl restart bind9
```

## Create Self signed certificates for internal services
```
openssl genrsa -aes256 -out montysplace_root_ca.key 4096

openssl req -x509 -new -nodes -key montysplace_root_ca.key -sha256 -days 3650 -out montysplace_root_ca.crt

openssl genrsa -out montysplace_wildcard.key 2048

echo "[v3_req]
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.montysplace.local
DNS.2 = montysplace.local" > montysplace_wildcard.ext

openssl req -new -key montysplace_wildcard.key -out montysplace_wildcard.csr -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:*.montysplace.local,DNS:montysplace.local"))

openssl x509 -req -in montysplace_wildcard.csr -CA montysplace_root_ca.crt -CAkey montysplace_root_ca.key -CAcreateserial -out montysplace_wildcard.crt -days 3650 -sha256 -extfile montysplace_wildcard.ext -extensions v3_req

```
## Grafana Loki and Alloy testing (not yet functional)
* Add Grafana repo and install Grafana loki and alloy
```
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt update; sudo apt install grafana alloy loki -y
```
* Setup web admin - default is admin/admin - https://syslog.montysplace.local:3000/
** Sign in and reset admin password to something more secure
```
sudo groupadd loki
sudo mkdir -p /var/lib/loki/index /var/lib/loki/cache /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
sudo chown -R loki:loki /var/lib/loki

sudo wget -O /etc/loki/config.yml https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/refs/heads/main/Loki/config.yml

sudo sed -i '/CUSTOM_ARGS=/c\CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"' /etc/default/alloy
sudo sed -i '/CONFIG_FILE=/c\CONFIG_FILE="/etc/alloy"' /etc/default/alloy

```
* Enable and start the new services
```
sudo systemctl start loki grafana alloy
sudo systemctl enable loki grafana alloy
```
* Setup rsyslogd
* Grab a custom rsyslog file for opening inbound logs and creating new logs under /var/log/external_logs/
```
mkdir -p /var/log/external_logs
chown syslog /var/log/external_logs
sudo wget -O /etc/rsyslog.d/remote_logging.conf https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/refs/heads/main/Rsyslog.d/remote_logging.conf
```
* Restart rsyslog
```
systemctl restart rsyslog
```
* Grab the alloy config file for log parsing
```
sudo wget -O /etc/alloy/config.alloy https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/refs/heads/main/Alloy/config.alloy
```

## Deploy Alloy to other nodes:
* Grab software and install
```
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt update; sudo apt install alloy -y
```
* Grab alloy config
```
sudo wget -O /etc/alloy/config.alloy https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/refs/heads/main/Alloy/config.alloy
sudo sed -i '/CUSTOM_ARGS=/c\CUSTOM_ARGS="--server.http.listen-addr=0.0.0.0:12345"' /etc/default/alloy
sudo sed -i '/CONFIG_FILE=/c\CONFIG_FILE="/etc/alloy"' /etc/default/alloy
sudo systemctl start alloy
sudo systemctl enable alloy
```
TODO: Determine ways to isolate appropriate data from foreign system for searching and aggregation
