#!/bin/bash
set -x
trap read debug

source setup_config

if [ "$node_type" == "controller" ]
then
   #
   # nova 
   #
   
   mysql -u root -p$password -e "CREATE DATABASE nova;"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$password';"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$password';"
   
   source admin-openrc.sh
   
   #
   # Create the nova user
   #
   openstack user create --password-prompt nova
   
   #
   # Add the admin role to the nova user
   #
   openstack role add --project service --user nova admin
   
   #
   # Create the nova service entity 
   #
   openstack service create \
     --name nova --description "OpenStack Compute" compute
   
   #
   # Create the Compute service API endpoint
   #
   openstack endpoint create \
     --publicurl http://controller:8774/v2/%\(tenant_id\)s \
     --internalurl http://controller:8774/v2/%\(tenant_id\)s \
     --adminurl http://controller:8774/v2/%\(tenant_id\)s \
     --region RegionOne \
     compute
   
   # Install the packages
   yum install -y -q openstack-nova-api openstack-nova-cert openstack-nova-conductor \
     openstack-nova-console openstack-nova-novncproxy openstack-nova-scheduler \
     python-novaclient
   
   #
   # Edit /etc/nova/nova.conf
   #
   cp /etc/nova/nova.conf /etc/nova/nova.conf.orig
   
   sed -i '/^\[database\]/a connection=mysql://nova:'$password'@controller/nova' /etc/nova/nova.conf
   
   sed -i '/^\[DEFAULT\]/a rpc_backend=rabbit' /etc/nova/nova.conf
   sed -i '/^\[oslo_messaging_rabbit\]/a rabbit_host=controller\nrabbit_userid=openstack\nrabbit_password='$password /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a auth_strategy=keystone' /etc/nova/nova.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=nova\npassword='$password /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a my_ip='$ip_addr /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a vncserver_listen='$ip_addr'\nvncserver_proxyclient_address='$ip_addr /etc/nova/nova.conf
   sed -i '/^\[glance\]/a host=controller' /etc/nova/nova.conf
   sed -i '/^\[oslo_concurrency\]/a lock_path=/var/lib/nova/tmp' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/nova/nova.conf
   
   #
   # Populate the Compute service database
   #
   su -s /bin/sh -c "nova-manage db sync" nova
   
   #
   # Start the Compute service and configure them to start when the system boots
   #
   systemctl enable openstack-nova-api.service openstack-nova-cert.service \
     openstack-nova-consoleauth.service openstack-nova-scheduler.service \
     openstack-nova-conductor.service openstack-nova-novncproxy.service
   systemctl start openstack-nova-api.service openstack-nova-cert.service \
     openstack-nova-consoleauth.service openstack-nova-scheduler.service \
     openstack-nova-conductor.service openstack-nova-novncproxy.service
   #
   # verify
   #

   source admin-openrc.sh

   nova service-list

   nova endpoints

   nova image-list
   
elif [ "$node_type" == "compute" ]
then
   #
   # Install the packages 
   #
   yum install -y -q openstack-nova-compute sysfsutils

   #
   # Edit /etc/nova/nova.conf
   #
   cp /etc/nova/nova.conf /etc/nova/nova.conf.orig
   
   sed -i '/^\[DEFAULT\]/a rpc_backend=rabbit' /etc/nova/nova.conf
   sed -i '/^\[oslo_messaging_rabbit\]/a rabbit_host=controller\nrabbit_userid=openstack\nrabbit_password='$password /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a auth_strategy=keystone' /etc/nova/nova.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=nova\npassword='$password /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a my_ip='$ip_addr /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a vnc_enabled=True\nvncserver_listen=0.0.0.0\nvncproxyclient_address='$ip_addr'\nnovncproxy_base_url=http://controller:6080/vnc_auto.html' /etc/nova/nova.conf
   sed -i '/^\[glance\]/a host=controller' /etc/nova/nova.conf
   sed -i '/^\[oslo_concurrency\]/a lock_path=/var/lib/nova/tmp' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/nova/nova.conf

   #
   # Start the Compute service including its dependencies and configure them to start automatically when the system boots
   #
   systemctl enable libvirtd.service openstack-nova-compute.service
   systemctl start libvirtd.service openstack-nova-compute.service
fi

