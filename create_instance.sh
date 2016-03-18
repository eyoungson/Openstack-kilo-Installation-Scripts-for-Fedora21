#!/bin/bash
set -x

trap read debug

source demo-openrc.sh

nova keypair-add demo-key

nova keypair-list

nova flavor-list

nova image-list

neutron net-list

nova secgroup-list


DEMO_NET_ID=$(neutron net-list | grep demo-net | cut -d '|' -f2 | cut -b2-)
nova boot --flavor m1.tiny --image cirros-0.3.4-x86_64 --nic net-id=$DEMO_NET_ID \
  --security-group default --key-name demo-key demo-instance1


nova list

nova get-vnc-console demo-instance1 novnc

