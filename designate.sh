#!/bin/bash

# designate.sh

# Authors: Kevin Jackson (@itarchitectkev)

# Source in common env vars
. /vagrant/common.sh


DESIGNATE_SERVICE_USER=designate
DESIGNATE_SERVICE_PASS=designate


############################
# DESIGNATE ADD-ON TO RPCO #
############################

# MySQL
export MYSQL_HOST=localhost
export MYSQL_ROOT_PASS=openstack
export MYSQL_DB_PASS=openstack

echo "mysql-server-5.5 mysql-server/root_password password $MYSQL_ROOT_PASS" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQL_ROOT_PASS" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password seen true" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again seen true" | sudo debconf-set-selections

sudo apt-get -y install mysql-server python-mysqldb

sudo sed -i "s/^bind\-address.*/bind-address = 0.0.0.0/g" /etc/mysql/my.cnf
sudo sed -i "s/^#max_connections.*/max_connections = 512/g" /etc/mysql/my.cnf

# Skip Name Resolve
echo "[mysqld]
skip-name-resolve" > /etc/mysql/conf.d/skip-name-resolve.cnf


# UTF-8 Stuff
echo "[mysqld]
collation-server = utf8_general_ci
init-connect='SET NAMES utf8'
character-set-server = utf8" > /etc/mysql/conf.d/01-utf8.cnf

sudo restart mysql

# Ensure root can do its job
mysql -u root -p${MYSQL_ROOT_PASS} -h localhost -e "GRANT ALL ON *.* to root@\"localhost\" IDENTIFIED BY \"${MYSQL_ROOT_PASS}\" WITH GRANT OPTION;"
mysql -u root -p${MYSQL_ROOT_PASS} -h localhost -e "GRANT ALL ON *.* to root@\"%\" IDENTIFIED BY \"${MYSQL_ROOT_PASS}\" WITH GRANT OPTION;"

mysqladmin -uroot -p${MYSQL_ROOT_PASS} flush-privileges


sudo apt-get -y install rabbitmq-server python-pip python-virtualenv git build-essential python-lxml libmysqlclient-dev

cd /var/lib
git clone https://github.com/openstack/designate.git
cd designate
pip install -r requirements.txt -r test-requirements.txt
python setup.py develop
cd etc/designate
ls *.sample | while read f; do cp $f $(echo $f | sed "s/.sample$//g"); done
mkdir /var/log/designate

cat designate.conf <<EOF
[DEFAULT]
########################
## General Configuration
########################
# Show more verbose log output (sets INFO log level output)
verbose = True

# Show debugging output in logs (sets DEBUG log level output)
debug = True

# Top-level directory for maintaining designate's state
state_path = /var/lib/designate

# Log directory
logdir = /var/log/designate

# Driver used for issuing notifications
notification_driver = messaging

# Use "sudo designate-rootwrap /etc/designate/rootwrap.conf" to use the real
# root filter facility.
# Change to "sudo" to skip the filtering and just run the comand directly
# root_helper = sudo

# RabbitMQ Config
rabbit_userid = designate
rabbit_password = designate
#rabbit_virtual_host = /
#rabbit_use_ssl = False
#rabbit_hosts = 127.0.0.1:5672

########################
## Service Configuration
########################
#-----------------------
# Central Service
#-----------------------
[service:central]
# Maximum domain name length
#max_domain_name_len = 255

# Maximum record name length
#max_record_name_len = 255

#-----------------------
# API Service
#-----------------------
[service:api]
# Address to bind the API server
api_host = 0.0.0.0

# Port to bind the API server
api_port = 9001

# Authentication strategy to use - can be either "noauth" or "keystone"
auth_strategy = noauth

# Enable API Version 1
enable_api_v1 = True

# Enable API Version 2
enable_api_v2 = True

# Enabled API Version 1 extensions
enabled_extensions_v1 = diagnostics, quotas, reports, sync, touch

# Enabled API Version 2 extensions
enabled_extensions_v2 = quotas, reports

#-----------------------
# mDNS Service
#-----------------------
[service:mdns]
#workers = None
#host = 0.0.0.0
#port = 5354
#tcp_backlog = 100

#-----------------------
# Pool Manager Service
#-----------------------
[service:pool_manager]
backends = bind9
#workers = None
pool_id = 794ccc2c-d751-44fe-b57f-8894c9f5c842
#threshold_percentage = 100
#poll_timeout = 30
#poll_retry_interval = 2
#poll_max_retries = 3
#poll_delay = 1
#periodic_recovery_interval = 120
#periodic_sync_interval = 300
#periodic_sync_seconds = None
#cache_driver = sqlalchemy

########################
## Storage Configuration
########################
#-----------------------
# SQLAlchemy Storage
#-----------------------
[storage:sqlalchemy]
# Database connection string - to configure options for a given implementation
# like sqlalchemy or other see below
connection = mysql://root:password@127.0.0.1/designate
#connection_debug = 100
#connection_trace = True
#sqlite_synchronous = True
#idle_timeout = 3600
#max_retries = 10
#retry_interval = 10

###################################
## Pool Manager Cache Configuration
###################################
#-----------------------
# SQLAlchemy Pool Manager Cache
#-----------------------
[pool_manager_cache:sqlalchemy]
connection = mysql://root:password@127.0.0.1/designate_pool_manager
#connection_debug = 100
#connection_trace = False
#sqlite_synchronous = True
#idle_timeout = 3600
#max_retries = 10
#retry_interval = 10

#############################
## Pool Backend Configuration
#############################
#-----------------------
# Global Bind9 Pool Backend
#-----------------------
[backend:bind9]
server_ids = 6a5032b6-2d96-43ee-b25b-7d784e2bf3b2
#masters = 127.0.0.1:5354
#rndc_host = 127.0.0.1
#rndc_port = 953
#rndc_config_file = /etc/rndc.conf
#rndc_key_file = /etc/rndc.key

#-----------------------
# Server Specific Bind9 Pool Backend
#-----------------------
[backend:bind9:6a5032b6-2d96-43ee-b25b-7d784e2bf3b2]
#host = 127.0.0.1
#port = 53
EOF

rabbitmqctl add_user designate designate
sudo rabbitmqctl set_permissions -p "/" designate ".*" ".*" ".*"

pip install mysql-python

cd /var/lib/designate
designate-manage database sync
designate-central &
sleep 2
designate-api &
sleep 2
designate-manage pool-manager-cache sync
designate-pool-manager &
designate-mdns &



#[keystone_authtoken]
#auth_uri = https://${KEYSTONE_ADMIN_ENDPOINT}:35357/v2.0/
#identity_uri = https://${KEYSTONE_ADMIN_ENDPOINT}:5000
#admin_tenant_name = ${SERVICE_TENANT}
#admin_user = ${CEILOMETER_SERVICE_USER}
#admin_password = ${CEILOMETER_SERVICE_PASS}
##signing_dir = \$state_path/keystone-signing
#insecure = True
#
#[service_credentials]
#os_auth_url = https://192.168.100.200:5000/v2.0
#os_username = ceilometer
#os_tenant_name = service
#os_password = ceilometer
#insecure = True
#
#EOF
#
#keystone user-create --name=ceilometer --pass=ceilometer --email=ceilometer@localhost
#keystone user-role-add --user=ceilometer --tenant=service --role=admin
#
#keystone service-create --name=ceilometer --type=metering --description="Ceilometer Metering Service"
#
#METERING_SERVICE_ID=$(keystone service-list | awk '/\ metering\ / {print $2}')
#
#keystone endpoint-create \
#  --region regionOne \
#  --service-id=${METERING_SERVICE_ID} \
#  --publicurl=http://${CONTROLLER_HOST}:8777 \
#  --internalurl=http://${CONTROLLER_HOST}:8777 \
#  --adminurl=http://${CONTROLLER_HOST}:8777
#
