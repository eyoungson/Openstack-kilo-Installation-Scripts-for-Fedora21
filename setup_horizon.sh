#!/bin/bash
set -x
trap read debug

source setup_config

if [ $node_type == "controller" ]
then
   #
   # horizon for controller
   #
   
   # Install the packages
   yum install -y -q openstack-dashboard httpd mod_wsgi memcached python-memcached
   
   
   #
   #Edit /etc/openstack-dashboard/local_settings
   #
   cp /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.orig
   
   sed -i 's/^OPENSTACK_HOST.*/OPENSTACK_HOST = "controller"/' /etc/openstack-dashboard/local_settings
   sed -i "s/^ALLOWED_HOSTS.*/ALLOWED_HOSTS = ['*', ]/" /etc/openstack-dashboard/local_settings
   sed -i "s/django.core.cache.backends.locmem.LocMemCache/django.core.cache.backends.memcached.MemcachedCache',\n        'LOCATION': '127.0.0.1:11211/"  /etc/openstack-dashboard/local_settings
   sed -i 's/^OPENSTACK_KEYSTONE_DEFAULT_ROLE.*/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"/' /etc/openstack-dashboard/local_settings
   sed -i 's/^TIME_ZONE.*/TIME_ZONE = "UTC"/' /etc/openstack-dashboard/local_settings

   #
   # Finalize
   #
   setsebool -P httpd_can_network_connect on

   chown -R apache:apache /usr/share/openstack-dashboard/static

   systemctl enable httpd.service memcached.service
   systemctl restart httpd.service memcached.service
fi

