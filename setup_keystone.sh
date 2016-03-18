#!/bin/bash
set -x
trap read debug

source setup_config

if [ "$node_type" == "controller" ]
then
   #
   # keystone for controller
   #
   mysql -u root -p$password -e "CREATE DATABASE keystone;"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$password';"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$password';"

   yum install -y -q openstack-keystone httpd mod_wsgi python-openstackclient memcached python-memcached

   systemctl enable memcached.service
   systemctl start memcached.service

   token=$(openssl rand -hex 10)

   #
   # Edit /etc/keystone/keystone.conf
   #
   cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.orig

   sed -i '/^\[DEFAULT\]/a admin_token='$token /etc/keystone/keystone.conf
   sed -i '/^\[database\]/a connection=mysql://keystone:'$password'@controller/keystone' /etc/keystone/keystone.conf
   sed -i '/^\[memcache\]/a servers = localhost:11211' /etc/keystone/keystone.conf
   sed -i '/^\[token\]/a provider = keystone.token.providers.uuid.Provider' /etc/keystone/keystone.conf
   sed -i '/^\[token\]/a driver = keystone.token.persistence.backends.memcache.Token' /etc/keystone/keystone.conf
   sed -i '/^\[revoke\]/a driver = keystone.contrib.revoke.backends.sql.Revoke' /etc/keystone/keystone.conf
   sed -i '/^\[DEFAULT\]/a verbose = True' /etc/keystone/keystone.conf

   #
   # Populate the Identity service database
   #
   su -s /bin/sh -c "keystone-manage db_sync" keystone

   #
   # Configure the Apache HHTP server
   #

   #
   # Edit /etc/httpd/conf/httpd.conf
   #
   cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.orig

   sed -i 's/^#ServerName.*/ServerName controller/' /etc/httpd/conf/httpd.conf


   #
   # Create /etc/httpd/conf.d/wsgi-keystone.conf
   #
   cat <<EOF > /etc/httpd/conf.d/wsgi-keystone.conf
   Listen 5000
   Listen 35357

   <VirtualHost *:5000>
       WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
       WSGIProcessGroup keystone-public
       WSGIScriptAlias / /var/www/cgi-bin/keystone/main
       WSGIApplicationGroup %{GLOBAL}
       WSGIPassAuthorization On
       LogLevel info
       ErrorLogFormat "%{cu}t %M"
       ErrorLog /var/log/httpd/keystone-error.log
       CustomLog /var/log/httpd/keystone-access.log combined
   </VirtualHost>

   <VirtualHost *:35357>
       WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
       WSGIProcessGroup keystone-admin
       WSGIScriptAlias / /var/www/cgi-bin/keystone/admin
       WSGIApplicationGroup %{GLOBAL}
       WSGIPassAuthorization On
       LogLevel info
       ErrorLogFormat "%{cu}t %M"
       ErrorLog /var/log/httpd/keystone-error.log
       CustomLog /var/log/httpd/keystone-access.log combined
   </VirtualHost>
EOF

   mkdir -p /var/www/cgi-bin/keystone

   curl http://git.openstack.org/cgit/openstack/keystone/plain/httpd/keystone.py?h=stable/kilo | tee /var/www/cgi-bin/keystone/main /var/www/cgi-bin/keystone/admin


   chown -R keystone:keystone /var/www/cgi-bin/keystone
   chmod 755 /var/www/cgi-bin/keystone/*

   systemctl enable httpd.service
   systemctl start httpd.service

   #
   # Create the service entity and API endpoint
   #
   export OS_TOKEN=$token
   export OS_URL=http://controller:35357/v2.0

   #
   # Create the service entity 
   #
   openstack service create \
     --name keystone --description "OpenStack Identity" identity

   #
   # Create the Identity service API endpoint
   #
   openstack endpoint create \
     --publicurl http://controller:5000/v2.0 \
     --internalurl http://controller:5000/v2.0 \
     --adminurl http://controller:35357/v2.0 \
     --region RegionOne \
     identity

   #
   # Create the admin project
   #
   openstack project create --description "Admin Project" admin

   #
   # Create the admin user
   #
   openstack user create --password-prompt admin

   #
   # Create the admin role
   #
   openstack role create admin

   #
   # Add the admin role to the admin project and user
   #
   openstack role add --project admin --user admin admin

   #
   # Create the service project
   #
   openstack project create --description "Service Project" service
   
   #
   # Create the demo project
   #
   openstack project create --description "Demo Project" demo
   
   #
   # Create the demo user
   #
   openstack user create --password-prompt demo
   
   #
   # Create the user role
   #
   openstack role create user
   
   #
   # Add the user role to the demo project and user
   #
   openstack role add --project demo --user demo user
   
   #
   # verify keystone
   #
   
   #
   # Edit /usr/share/keystone/keystone-dist-paste.ini
   #
   cp /usr/share/keystone/keystone-dist-paste.ini /usr/share/keystone/keystone-dist-paste.ini.orig
   
   sed -i '/^\[pipeline:public_api\]/,/\[pipeline:admin_api\]/s/^pipeline\ =.*/pipeline = sizelimit url_normalize request_id build_auth_context token_auth json_body ec2_extension user_crud_extension public_service/' /usr/share/keystone/keystone-dist-paste.ini
   sed -i '/^\[pipeline:admin_api\]/,/\[pipeline:api_v3\]/s/^pipeline\ =.*/pipeline = sizelimit url_normalize request_id build_auth_context token_auth json_body ec2_extension s3_extension crud_extension admin_service/' /usr/share/keystone/keystone-dist-paste.ini
   sed -i '/^\[pipeline:api_v3\]/,/\[app:public_version_service\]/s/^pipeline\ =.*/pipeline = sizelimit url_normalize request_id build_auth_context token_auth json_body ec2_extension_v3 s3_extension simple_cert_extension revoke_extension federation_extension oauth1_extension endpoint_filter_extension endpoint_policy_extension service_v3/' /usr/share/keystone/keystone-dist-paste.ini
    
   unset OS_TOKEN OS_URL
   
   openstack --os-auth-url http://controller:35357 \
     --os-project-name admin --os-username admin --os-auth-type password \
     token issue
   
   openstack --os-auth-url http://controller:35357 \
     --os-project-domain-id default --os-user-domain-id default \
     --os-project-name admin --os-username admin --os-auth-type password \
     token issue
   
   
   openstack --os-auth-url http://controller:35357 \
     --os-project-name admin --os-username admin --os-auth-type password \
     project list
   
   
   openstack --os-auth-url http://controller:35357 \
     --os-project-name admin --os-username admin --os-auth-type password \
     user list
   
   
   openstack --os-auth-url http://controller:35357 \
     --os-project-name admin --os-username admin --os-auth-type password \
     role list
   
   
   openstack --os-auth-url http://controller:5000 \
     --os-project-domain-id default --os-user-domain-id default \
     --os-project-name demo --os-username demo --os-auth-type password \
     token issue
   
   
   openstack --os-auth-url http://controller:5000 \
     --os-project-domain-id default --os-user-domain-id default \
     --os-project-name demo --os-username demo --os-auth-type password \
     user list
   
   echo -e "the last ERROR is OK!\n"

   source admin-openrc.sh

   openstack token issue
fi
