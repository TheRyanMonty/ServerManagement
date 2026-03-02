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

* Setup Backup
Setup backup script to backup the the directories and move off node (to NAS) on primary dns server
```
tar -czf $LOCAL_FILE /etc/bind /var/lib/bind
```

* Setup TSIG encryption between primary and secondary DNS servers for security during syncronization
* Run this from primary dns server
```
tsig-keygen -a HMAC-SHA256 tsig-key > /etc/bind/tsig.key
chown root:bind /etc/bind/tsig.key
chmod 640 /etc/bind/tsig.key
```
* Include the key on the primary dns server: At the top of /etc/bind/named.conf.local, add:
```
include "/etc/bind/tsig.key";
```
* Add this line in primary and reverse lookup zones:
```
allow-transfer { key "tsig-key"; };
````
example:
```
zone "montysplace.local" {
    type master;
    file "/etc/bind/db.montysplace.local";
    allow-transfer { key "tsig-key"; }; # Replaces the IP address
};
```
* On secondary node:
```
echo 'key "tsig-key" {
        algorithm hmac-sha256;
        secret "m50yYW6E5gKAiwJhxj6wQ24R/2ZC1AoqCddqx11mM/o=";
};'>/etc/bind/tsig.key

chown root:bind /etc/bind/tsig.key
chmod 640 /etc/bind/tsig.key
```
* Include the key and server clause in /etc/bind/named.conf.local
```
include "/etc/bind/tsig.key";

server 10.50.1.19 {
    keys { "tsig-key"; };
};
```

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
* Install prometheus
```
apt-get install prometheus -y
```
* Grab configuration files
```
sudo wget -O /etc/systemd/system/prometheus.service https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/refs/heads/main/Prometheus/prometheus.service
sudo wget -O /etc/prometheus/prometheus.yml https://raw.githubusercontent.com/TheRyanMonty/ServerManagement/refs/heads/main/Prometheus/prometheus.yml
```

## Deploy NextCloud
* Setup NFS to NAS devices
Example /etc/fstab entry
```
10.50.1.20:/volume1/NextCloud  /mnt/nextcloud  nfs  defaults,nofail,_netdev,x-systemd.automount  0  0
```
* Ensure docker is installed and rollout mariadb and nextcloud, ensure only 443 is reachable
```
sudo apt install docker.io -y

sudo chown -R 33:33 /mnt
sudo chmod -R 750 /mnt

# Deploy MariaDB container
docker run -d \
  --name nextcloud-db \
  --restart always \
  -v nextcloud_mysql:/var/lib/mysql \
  -e MYSQL_ROOT_PASSWORD="<PASSWORD>" \
  -e MYSQL_DATABASE=nextcloud \
  -e MYSQL_USER=nextcloud \
  -e MYSQL_PASSWORD="<PASSWORD>" \
  mariadb:10.6 --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW

# Start the container
docker run -d \
  --name nextcloud-local \
  -p 8443:443 \
  --link nextcloud-db:db \
  -v nextcloud_config:/var/www/html \
  -v /mnt/nextcloud:/var/www/html/data \
  -v /etc/ssl/montysplace/fullchain.pem:/etc/apache2/ssl/nextcloud.crt \
  -v /etc/ssl/montysplace/privkey.pem:/etc/apache2/ssl/nextcloud.key \
  --restart always \
  -e NEXTCLOUD_TRUSTED_DOMAINS="servermgr1.montysplace.local" \
  -e NEXTCLOUD_ADMIN_USER="monty" \
  -e NEXTCLOUD_ADMIN_PASSWORD="<PASSWORD>" \
  -e MYSQL_DATABASE=nextcloud \
  -e MYSQL_USER=nextcloud \
  -e MYSQL_PASSWORD="<PASSWORD>" \
  -e MYSQL_HOST=db \
  -e PHP_MEMORY_LIMIT=2G \
  -e PHP_UPLOAD_LIMIT=10G \
  -e APACHE_BODY_LIMIT=1073741824 \
  nextcloud

# 2. Enable the SSL module, fix the config file paths and restart apache in the container
docker exec -u 0 nextcloud-local a2enmod ssl
docker exec -u 0 nextcloud-local sed -i 's|/etc/ssl/certs/ssl-cert-snakeoil.pem|/etc/apache2/ssl/nextcloud.crt|g' /etc/apache2/sites-available/default-ssl.conf
docker exec -u 0 nextcloud-local sed -i 's|/etc/ssl/private/ssl-cert-snakeoil.key|/etc/apache2/ssl/nextcloud.key|g' /etc/apache2/sites-available/default-ssl.conf
docker exec -u 0 nextcloud-local a2ensite default-ssl
docker exec -u 0 nextcloud-local service apache2 restart

#Nuclear command for docker docker system prune -a --volumes
```

* Open the web interface at https://servermgr1.montysplace.local:8443

