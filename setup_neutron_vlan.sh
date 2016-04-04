#!/bin/bash
set -x
trap read debug

source setup_config

if [ "$node_type" == "controller" ]
then
   #
   # neutron 
   #
   
   mysql -u root -p$password -e "CREATE DATABASE neutron;"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$password';"
   mysql -u root -p$password -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$password';"
   
   source admin-openrc.sh
   
   #
   # Create the neutron user
   #
   openstack user create --password-prompt neutron
   
   #
   # Add the admin role to the neutron user
   #
   openstack role add --project service --user neutron admin
   
   #
   # Create the neutron service entity 
   #
   openstack service create \
     --name neutron --description "OpenStack Networking" network
   
   #
   # Create the Networking service API endpoint
   #
   openstack endpoint create \
     --publicurl http://controller:9696 \
     --internalurl http://controller:9696 \
     --adminurl http://controller:9696 \
     --region RegionOne \
     network
   
   # Install the packages
   yum install -y -q openstack-neutron openstack-neutron-ml2 python-neutronclient which
   
   #
   # Edit /etc/neutron/neutron.conf
   #
   cp  /etc/neutron/neutron.conf  /etc/neutron/neutron.conf.orig
   
   sed -i '/^\[DEFAULT\]/a core_plugin=ml2\nservice_plugins=router\nallow_overlapping_ips=True' /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a auth_strategy=keystone' /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a rpc_backend=rabbit' /etc/neutron/neutron.conf
   sed -i 's/^auth_uri/#auth_uri/' /etc/neutron/neutron.conf
   sed -i 's/^identity_uri/#identity_uri/' /etc/neutron/neutron.conf
   sed -i 's/^admin_tenant_name/#admin_tenant_name/' /etc/neutron/neutron.conf
   sed -i 's/^admin_user/#admin_user/' /etc/neutron/neutron.conf
   sed -i 's/^admin_password/#admin_password/' /etc/neutron/neutron.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=neutron\npassword='$password /etc/neutron/neutron.conf
   sed -i '/^\[database\]/a connection=mysql://neutron:'$password'@controller/neutron' /etc/neutron/neutron.conf
   sed -i '/^\[nova\]/a auth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nregion_name=RegionOne\nproject_name=service\nusername=nova\npassword='$password /etc/neutron/neutron.conf
   sed -i '/^\[oslo_messaging_rabbit\]/a rabbit_host=controller\nrabbit_userid=openstack\nrabbit_password='$password /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a notify_nova_on_port_status_changes=True\nnotify_nova_on_port_data_changes=True\nnova_url=http://controller:8774/v2' /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/neutron/neutron.conf
   
   #
   # Edit /etc/neutron/plugins/ml2/ml2_conf.ini
   #
   cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
   
   sed -i '/^\[ml2\]/a type_drivers=flat,vlan,gre,vxlan' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[ml2\]/a tenant_network_types=vlan,gre' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[ml2\]/a mechanism_drivers=openvswitch' /etc/neutron/plugins/ml2/ml2_conf.ini
#  sed -i '/^\[ml2_type_gre\]/a tunnel_id_ranges=1:1000' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[ml2_type_vlan\]/a network_vlan_ranges=physnet1:1000:2999' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[securitygroup\]/a enable_security_group=True\nenable_ipset=True\nfirewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver' /etc/neutron/plugins/ml2/ml2_conf.ini
   
   
   #
   # Edit /etc/nova/nova.conf
   #
   sed -i '/^\[DEFAULT\]/a network_api_class=nova.network.neutronv2.api.API' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a security_group_api = neutron' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a firewall_driver = nova.virt.firewall.NoopFirewallDriver' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a url=http://controller:9696' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a auth_strategy=keystone' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_auth_url=http://controller:35357/v2.0' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_tenant_name=service' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_username=neutron' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_password='$password /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a service_metadata_proxy=True\nmetadata_proxy_shared_secret='$password /etc/nova/nova.conf
   

   ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
   
   
   #
   # Populate the Networking service database
   #
   su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
   
   #
   # Restart the Compute services
   #
   systemctl restart openstack-nova-api.service openstack-nova-scheduler.service \
     openstack-nova-conductor.service
   
   #
   # Start the Compute service and configure them to start when the system boots
   #
   systemctl enable neutron-server.service
   systemctl start neutron-server.service
   
   #
   # verify neutron
   #
   source  admin-openrc.sh
   
   neutron ext-list
   neutron agent-list

elif [ "$node_type" == "network" ]
then
   #
   # Configure prerequisites
   #
   #
   # Edit /etc/sysctl.conf
   #
   sed -i '$a net.ipv4.ip_forward=1\nnet.ipv4.conf.all.rp_filter=0\nnet.ipv4.conf.default.rp_filter=0' /etc/sysctl.conf

   # Implement the changes
   sysctl -p

   #
   # install the Networking components
   #
   yum install -y -q openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch

   #
   # Configure the Networking common components
   #

   #
   # Edit /etc/neutron/neutron.conf
   #
   cp  /etc/neutron/neutron.conf  /etc/neutron/neutron.conf.orig

   sed -i '/^\[DEFAULT\]/a core_plugin=ml2\nservice_plugins=router\nallow_overlapping_ips=True' /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a auth_strategy=keystone' /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a rpc_backend=rabbit' /etc/neutron/neutron.conf
   sed -i 's/^auth_uri/#auth_uri/' /etc/neutron/neutron.conf
   sed -i 's/^identity_uri/#identity_uri/' /etc/neutron/neutron.conf
   sed -i 's/^admin_tenant_name/#admin_tenant_name/' /etc/neutron/neutron.conf
   sed -i 's/^admin_user/#admin_user/' /etc/neutron/neutron.conf
   sed -i 's/^admin_password/#admin_password/' /etc/neutron/neutron.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=neutron\npassword='$password /etc/neutron/neutron.conf
   sed -i '/^\[oslo_messaging_rabbit\]/a rabbit_host=controller\nrabbit_userid=openstack\nrabbit_password='$password /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/neutron/neutron.conf

   #
   # Configure the Modular Layer 2 (ML2) plug-in
   #
   #
   # Edit /etc/neutron/plugins/ml2/ml2_conf.ini
   #
   cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
   
   sed -i '/^\[ml2\]/a type_drivers=flat,vlan,gre,vxlan\ntenant_network_types=vlan,gre\nmechanism_drivers=openvswitch' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[ml2_type_flat\]/a flat_networks=external' /etc/neutron/plugins/ml2/ml2_conf.ini
#   sed -i '/^\[ml2_type_gre\]/a tunnel_id_ranges=1:1000' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[ml2_type_vlan\]/a network_vlan_ranges=physnet1:1000:2999' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[securitygroup\]/a enable_security_group=True\nenable_ipset=True\nfirewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver' /etc/neutron/plugins/ml2/ml2_conf.ini
#   sed -i '$a [ovs]\nlocal_ip='$tenant_ip_addr'\nbridge_mappings=external:br-ex' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '$a [ovs]\ntenant_network_type=vlan\nbridge_mappings=physnet1:br-'$tenant_net_if',external:br-ex' /etc/neutron/plugins/ml2/ml2_conf.ini
#   sed -i '$a [agent]\ntunnel_types=gre' /etc/neutron/plugins/ml2/ml2_conf.ini

   #
   # Configure the Layer-3 (L3) agent
   #

   #
   # Edit /etc/neutron/l3_agent.ini
   #
   cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig

   sed -i '/^\[DEFAULT\]/a interface_driver=neutron.agent.linux.interface.OVSInterfaceDriver\nexternal_network_bridge=\nrouter_delete_namespaces=True' /etc/neutron/l3_agent.ini
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/neutron/l3_agent.ini
   
   #
   # Configure the DHCP agent
   #

   #
   # Edit /etc/neutron/dhcp_agent.ini
   #
   cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.orig

   sed -i '/^\[DEFAULT\]/a interface_driver=neutron.agent.linux.interface.OVSInterfaceDriver\ndhcp_driver=neutron.agent.linux.dhcp.Dnsmasq\ndhcp_delete_namespaces=True' /etc/neutron/dhcp_agent.ini
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/neutron/dhcp_agent.ini

   #
   # MTU for GRE
   #
   sed -i '/^\[DEFAULT\]/a dnsmasq_config_file=/etc/neutron/dnsmasq-neutron.conf' /etc/neutron/dhcp_agent.ini

   #
   # Create /etc/neutron/dnsmasq-neutron.conf
   cat <<EOF > /etc/neutron/dnsmasq-neutron.conf
dhcp-option-force=26,1454
EOF

   pkill dnsmasq

   #
   # Configure the metadata agent
   #

   #
   # Edit /etc/neutron/metadata_agent.ini
   #
   cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.orig

   sed -i '/^\[DEFAULT\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_region = RegionOne\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=neutron\npassword='$password  /etc/neutron/metadata_agent.ini
   sed -i '/^\[DEFAULT\]/a nova_metadata_ip=controller' /etc/neutron/metadata_agent.ini
   sed -i '/^\[DEFAULT\]/a metadata_proxy_shared_secret=zxcv!@34' /etc/neutron/metadata_agent.ini
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/neutron/metadata_agent.ini

   #
   # Configure the Open vSwitch (OVS) service
   #

   # Start the OVS service and configure it to start when the system boot
   systemctl enable openvswitch.service
   systemctl start openvswitch.service

   # Add the integration bridge 
   ovs-vsctl add-br br-int

   # Add the integration bridge 
   ovs-vsctl add-br br-$tenant_net_if

   ovs-vsctl add-port br-$tenant_net_if $tenant_net_if

   

   # Add the external bridge
   ovs-vsctl add-br br-ex

   # Add a port to the external bridge that connects to the physical external network interface
   ovs-vsctl add-port br-ex $external_net_if
 
   #
   # ethtool -K $external_net_if gro off

   #
   # Finalize the installation
   #
   ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

   #
   # Edit /usr/lib/systemd/system/neutron-openvswitch-agent.service
   #
   cp /usr/lib/systemd/system/neutron-openvswitch-agent.service \
      /usr/lib/systemd/system/neutron-openvswitch-agent.service.orig

   sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' \
      /usr/lib/systemd/system/neutron-openvswitch-agent.service

   systemctl enable neutron-openvswitch-agent.service neutron-l3-agent.service \
      neutron-dhcp-agent.service neutron-metadata-agent.service \
      neutron-ovs-cleanup.service
   systemctl start neutron-openvswitch-agent.service neutron-l3-agent.service \
      neutron-dhcp-agent.service neutron-metadata-agent.service

elif [ "$node_type" == "compute" ]
then
   #
   # Configure prerequisites
   #
   #
   # Edit /etc/sysctl.conf
   #
   sed -i '$a net.ipv4.ip_forward=1\nnet.ipv4.conf.all.rp_filter=0\nnet.ipv4.conf.default.rp_filter=0' /etc/sysctl.conf

   # Implement the changes
   sysctl -p

   #
   # install the Networking components
   #
   yum install -y -q openstack-neutron openstack-neutron-ml2 openstack-neutron-openvswitch

   #
   # Configure the Networking common components
   #

   #
   # Edit /etc/neutron/neutron.conf
   #
   cp  /etc/neutron/neutron.conf  /etc/neutron/neutron.conf.orig
   
   sed -i '/^\[DEFAULT\]/a rpc_backend=rabbit' /etc/neutron/neutron.conf
   sed -i '/^\[oslo_messaging_rabbit\]/a rabbit_host=controller\nrabbit_userid=openstack\nrabbit_password='$password /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a auth_strategy=keystone' /etc/neutron/neutron.conf
   sed -i 's/^auth_uri/#auth_uri/' /etc/neutron/neutron.conf
   sed -i 's/^identity_uri/#identity_uri/' /etc/neutron/neutron.conf
   sed -i 's/^admin_tenant_name/#admin_tenant_name/' /etc/neutron/neutron.conf
   sed -i 's/^admin_user/#admin_user/' /etc/neutron/neutron.conf
   sed -i 's/^admin_password/#admin_password/' /etc/neutron/neutron.conf
   sed -i '/^\[keystone_authtoken\]/a auth_uri=http://controller:5000\nauth_url=http://controller:35357\nauth_plugin=password\nproject_domain_id=default\nuser_domain_id=default\nproject_name=service\nusername=neutron\npassword='$password /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a core_plugin=ml2\nservice_plugins=router\nallow_overlapping_ips=True' /etc/neutron/neutron.conf
   sed -i '/^\[DEFAULT\]/a verbose=True' /etc/neutron/neutron.conf

   #
   # Configure the Modular Layer 2 (ML2) plug-in
   #
   #
   # Edit /etc/neutron/plugins/ml2/ml2_conf.ini
   #
   cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
   
   sed -i '/^\[ml2\]/a type_drivers=flat,vlan,gre,vxlan\ntenant_network_types=vlan,gre\nmechanism_drivers=openvswitch' /etc/neutron/plugins/ml2/ml2_conf.ini
#   sed -i '/^\[ml2_type_gre\]/a tunnel_id_ranges=1:1000' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[ml2_type_vlan\]/a network_vlan_ranges=physnet1:1000:2999' /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '/^\[securitygroup\]/a enable_security_group=True\nenable_ipset=True\nfirewall_driver=neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver' /etc/neutron/plugins/ml2/ml2_conf.ini
#   sed -i '$a [ovs]\nlocal_ip='$tenant_ip_addr /etc/neutron/plugins/ml2/ml2_conf.ini
   sed -i '$a [ovs]\ntenant_network_type=vlan\nbridge_mappings=physnet1:br-'$tenant_net_i
#   sed -i '$a [agent]\ntunnel_types=gre' /etc/neutron/plugins/ml2/ml2_conf.ini

   #
   # Start the OVS service and configure it to start when the system boot
   #
   systemctl enable openvswitch.service
   systemctl start openvswitch.service


   # Add the integration bridge 
   ovs-vsctl add-br br-int

   # Add the integration bridge 
   ovs-vsctl add-br br-$tenant_net_if

   ovs-vsctl add-port br-$tenant_net_if $tenant_net_if


   #
   # Edit /etc/nova/nova.conf
   #
   sed -i '/^\[DEFAULT\]/a network_api_class=nova.network.neutronv2.api.API' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a security_group_api = neutron' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver' /etc/nova/nova.conf
   sed -i '/^\[DEFAULT\]/a firewall_driver = nova.virt.firewall.NoopFirewallDriver' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a url=http://controller:9696 ' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a auth_strategy=keystone' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_auth_url=http://controller:35357/v2.0' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_tenant_name=service' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_username=neutron' /etc/nova/nova.conf
   sed -i '/^\[neutron\]/a admin_password='$password /etc/nova/nova.conf
   

   #
   # Finalize the installation
   #
   ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini

   #
   # Edit /usr/lib/systemd/system/neutron-openvswitch-agent.service
   #
   cp /usr/lib/systemd/system/neutron-openvswitch-agent.service \
      /usr/lib/systemd/system/neutron-openvswitch-agent.service.orig

   sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' \
      /usr/lib/systemd/system/neutron-openvswitch-agent.service

   #
   # Restart the Compute service
   #
   systemctl restart openstack-nova-compute.service

   #
   # Start the Open vSwitch (OVS) agent and configure it to start when the system boots
   # 
   systemctl enable neutron-openvswitch-agent.service
   systemctl start neutron-openvswitch-agent.service
fi
