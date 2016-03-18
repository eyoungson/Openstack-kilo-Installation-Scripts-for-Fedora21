#!/bin/bash
set -x
trap read debug

source setup_config
source  admin-openrc.sh

#
#  create the external network
#
neutron net-create ext-net --router:external \
  --provider:physical_network external --provider:network_type flat

#
# create a subnet on the external network
#
neutron subnet-create ext-net $EXTERNAL_NETWORK_CIDR --name ext-subnet \
  --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END \
  --disable-dhcp --gateway $EXTERNAL_NETWORK_GATEWAY


source demo-openrc.sh

#
#  create the tenant network
#
neutron net-create demo-net


#
# create a subnet on the tenant network
#
neutron subnet-create demo-net $TENANT_NETWORK_CIDR \
  --name demo-subnet --dns-nameserver $DNS_RESOLVER \
  --gateway $TENANT_NETWORK_GATEWAY

#
# create a router on the tenant network and attach the external and tenant networks to it
#
neutron router-create demo-router

neutron router-interface-add demo-router demo-subnet

neutron router-gateway-set demo-router ext-net


#
# verify
#

