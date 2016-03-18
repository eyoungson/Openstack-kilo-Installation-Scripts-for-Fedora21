#!/bin/bash
set -x
trap read debug

source setup_config

if [ "$node_type" == "controller" ]
then
   #
   # mysql 
   #
   yum install -y -q mariadb mariadb-server MySQL-python

   #
   # Create /etc/my.cnf.d/mariadb-openstack.cnf
   cat <<EOF > /etc/my.cnf.d/mariadb-openstack.cnf  
   [mysqlld]
      bind-address=
      default-storage-engine=innodb
      innodb_file_per_table
      collation-server=utf8_general_ci
      init-connect='SET NAMES utf8'
      character-set-server=utf8
EOF

   sed -i 's/bind-address=/bind-address='$ip_addr'/g' /etc/my.cnf.d/mariadb-openstack.cnf  

   systemctl enable mariadb.service
   systemctl start mariadb.service

   mysql_secure_installation

   #
   # message queue 
   #
   yum install -y -q rabbitmq-server

   systemctl enable rabbitmq-server.service
   systemctl start rabbitmq-server.service

   rabbitmqctl add_user openstack $password

   rabbitmqctl set_permissions openstack ".*" ".*" ".*"
fi
