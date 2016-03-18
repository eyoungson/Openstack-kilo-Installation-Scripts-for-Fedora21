#!/bin/bash
set -x
trap read debug

source setup_config

if [ "$node_type" == "controller" ]
then
   #
   # glance for controller
   #
   
   mysql -u root -p$password -e "CREATE DATABASE glance;"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$password';"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$password';"
   
   #
   source admin-openrc.sh
   
   #
   # Create the glance user
   #
   openstack user create --password-prompt glance
   
   #
   # Add the admin role to the glance user
   #
   openstack role add --project service --user glance admin
   
   #
   # Create the service entity 
   #
   openstack service create \
     --name glance --description "OpenStack Image" image
   
   #
   # Create the Image service API endpoint
   #
   openstack endpoint create \
     --publicurl http://controller:9292 \
     --internalurl http://controller:9292 \
     --adminurl http://controller:9292 \
     --region RegionOne \
     image
   
   #
   # Install the packages
   #
   yum install -y -q openstack-glance python-glance python-glanceclient
   
   #
   # Edit /etc/glance/glance-api.conf
   #
   cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.orig
   
   sed -i '/^\[database\]/a connection=mysql://glance:'$password'@controller/glance' /etc/glance/glance-api.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=glance\npassword='$password /etc/glance/glance-api.conf
   sed -i '/^\[paste_deploy\]/a flavor=keystone' /etc/glance/glance-api.conf
   sed -i '/^\[glance_store\]/a default_store=file\nfilesystem_store_datadir=/var/lib/glance/images/' /etc/glance/glance-api.conf
   sed -i '/^\[DEFAULT\]/a notification_driver=noop' /etc/glance/glance-api.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/glance/glance-api.conf
   
   #
   # Edit /etc/glance/glance-registry.conf
   #
   cp /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.orig
   
   sed -i '/^\[database\]/a connection=mysql://glance:'$password'@controller/glance' /etc/glance/glance-registry.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=glance\npassword='$password /etc/glance/glance-registry.conf
   sed -i '/^\[DEFAULT\]/a notification_driver=noop' /etc/glance/glance-registry.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/glance/glance-registry.conf
   sed -i '/^\[paste_deploy\]/a flavor=keystone' /etc/glance/glance-registry.conf
   
   #
   # Populate the Image service database
   #
   su -s /bin/sh -c "glance-manage db_sync" glance
   
   #
   # Start the Image service and configure them to start when the system boots
   #
   systemctl enable openstack-glance-api.service openstack-glance-registry.service
   systemctl start openstack-glance-api.service openstack-glance-registry.service
   
   #
   # verify glance
   #
   echo "export OS_IMAGE_API_VERSION=2" | tee -a admin-openrc.sh demo-openrc.sh 

   source admin-openrc.sh
   mkdir /tmp/images
   wget -P /tmp/images http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
   glance image-create --name "cirros-0.3.4-x86_64" --file /tmp/images/cirros-0.3.4-x86_64-disk.img \
     --disk-format qcow2 --container-format bare --visibility public --progress
   glance image-list
   rm -r /tmp/images
fi

