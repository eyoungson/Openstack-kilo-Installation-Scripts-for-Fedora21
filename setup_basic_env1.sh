#!/bin/bash
set -x
trap read debug

source setup_config

#
# configure networking
#
# mgmt_net_if - used for openstack management
# tenant_net_if - used for openstack tenant network
# external_net_if - used for openstack public network for external connections

#
# Edit /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
# 
cp /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if.orig

onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if`
proto=`grep BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if`
sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
sed -i 's/'$proto'/BOOTPROTO=static/' /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if

ip=`grep IPADDR /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if`
if [ "$ip" == "" ]
then
  echo "IPADDR=$ip_addr" >> /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
else
   sed -i 's/'$ip'/IPADDR='$ip_addr'/g' /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
fi

gateway=`grep GATEWAY /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if`
if [ "$gateway" == "" ]
then
  echo "GATEWAY=$gateway_addr" >> /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
else
   sed -i 's/'$gateway'/GATEWAY='$gateway_addr'/g' /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
fi

x=`grep PREFIX /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if`
if [ "$x" == "" ]
then
  echo "PREFIX=$prefix" >> /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
else
   sed -i 's/'$x'/PREFIX='$prefix'/g' /etc/sysconfig/network-scripts/ifcfg-$mgmt_net_if
fi

#
# Edit /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if
# 
if [ "$node_type" != "controller" ]
then
   onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if`
   proto=`grep BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if`
   sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if
   sed -i 's/'$proto'/BOOTPROTO=static/' /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if

   ip=`grep IPADDR /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if`
   if [ "$ip" == "" ]
   then
     echo "IPADDR=$tenant_ip_addr" >> /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if
   else
      sed -i 's/'$ip'/IPADDR='$tenant_ip_addr'/g' /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if
   fi

   x=`grep PREFIX /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if`
   if [ "$x" == "" ]
   then
     echo "PREFIX=$tenant_prefix" >> /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if
   else
      sed -i 's/'$x'/PREFIX='$tenant_prefix'/g' /etc/sysconfig/network-scripts/ifcfg-$tenant_net_if
   fi

  ifup $tenant_net_if
fi


#
# Edit /etc/sysconfig/network-scripts/ifcfg-$external_net_if
# 
if [ "$node_type" == "network" ]
then
   onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$external_net_if`
   proto=`grep BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-$external_net_if`
   sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$external_net_if
   sed -i 's/'$proto'/BOOTPROTO=none/' /etc/sysconfig/network-scripts/ifcfg-$external_net_if

   ifup $external_net_if
fi

#
# Edit /etc/hosts 
#
cp /etc/hosts /etc/hosts.orig

echo "$controller_ip controller" >> /etc/hosts
echo "$network_ip network" >> /etc/hosts
echo "$compute1_ip compute1" >> /etc/hosts


systemctl restart NetworkManager.service

#
# Edit /etc/selinux/config
#
cp /etc/selinux/config /etc/selinux/config.orig

sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

#
# disable firewalld
#
systemctl stop firewalld.service
systemctl disable firewalld.service

#
# disable NetworkManager
#
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service

#
# enable network service
#
chkconfig network on

ifup $mgmt_net_if 
ifup $tenant_net_if 

#
# verify mgmt_net_if
#
ping -c 4 openstack.org

#
# Edit /etc/ntp.conf
#
cp /etc/ntp.conf /etc/ntp.conf.orig

echo "server $ntp_server_name" >> /etc/ntp.conf

sed -i 's/server 0.fedora.pool.ntp.org iburst/#server 0.fedora.pool.ntp.org/g' /etc/ntp.conf
sed -i 's/server 1.fedora.pool.ntp.org iburst/#server 1.fedora.pool.ntp.org/g' /etc/ntp.conf
sed -i 's/server 2.fedora.pool.ntp.org iburst/#server 2.fedora.pool.ntp.org/g' /etc/ntp.conf
sed -i 's/server 3.fedora.pool.ntp.org iburst/#server 3.fedora.pool.ntp.org/g' /etc/ntp.conf

sed -i 's/restrict default nomodify notrap nopeer noquery/restrict default nomodify notrap/g' /etc/ntp.conf

# enable and start ntp
systemctl enable ntpd.service
systemctl start ntpd.service

# verify ntp
ntpq -c peers
ntpq -c assoc

#
# enable openstack repository
#
yum install -y -q http://rdo.fedorapeople.org/openstack-kilo/rdo-release-kilo.rpm

#
# upgrade
#
yum upgrade -y 

#
# done 
#
echo -e "done system setup1 and upgrade \n"
echo -e " next steps : \n"
echo -e "         1. reboot the system\n"
echo -e "         2. run script 'setup_basic_env2.sh'"
