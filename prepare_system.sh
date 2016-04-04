#!/bin/bash
#
# Copyright (c) 2015, Intel Corporation
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#    * Redistributions of source code must retain the above copyright notice,
#      this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of Intel Corporation nor the names of its contributors
#      may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
echo "Before running this script, you must edit file 'onps_config'"
echo -e "and enter system specific information \n "

read -p "If you are ready, press 'y' or 'Y' to continue " response
case $response in
    [yY]* ) echo -e "start preparing fedora system \n" ;;
    * ) echo -e "exit to edit onps_config file \n "; exit;;
esac

# import necessary system information
# set to lower case for node_type and ovs_type
typeset -l node_type ovs_type
source onps_config

# validate node type and ovs type before moving on
if [ "$node_type" != "controller" ] && [ "$node_type" != "compute" ]
then
  echo -e "node_type you entered is $node_type "
  echo -e "wrong node type; it must be controller or compute  "
  echo -e "please modify onps_conf file and try again "
  echo -e "exit prepare_system now \n"
  exit 1
fi

if [ "$node_type" == "compute" ]
then
  if [ "$ovs_type" != "ovs" ] && [ "$ovs_type" != "ovs-dpdk" ]
  then
    echo -e "ovs_type you entered is $ovs_type "
    echo -e "wrong ovs type; it must be ovs or ovs-dpdk  "
    echo -e "please modify onps_config file and try again "
    echo -e "exit prepare_system now \n"
    exit 1
  fi
fi

# ======================================
# perform the following as 'su' user


# rename network interface for easier use in the script
net1=$mgmt_net_if
net2=$inter_net_if 
net3=$virtual_net_if 
net4=$public_net_if 

# other infomation
file_path=$PWD

# set host name by editing /etc/hostname
echo -e "set host name \n"
existing_name=`cat /etc/hostname`
sed -i 's/'$existing_name'/'$host_name'/g' /etc/hostname
sleep 1
echo -e "done change host name \n"

set -x 
trap read  debug

# configure networking, edit /etc/sysconfig/network-scripts/ifcfg-net-interface
# four netwrok interfaces to be configured 
#  net1 - used for openstack management
#  net2 - used for Internet network, pulling packages from all repositories
#  net3 - used for openstack virtual network (tenant network)
#  net4 - used for openstack public network for external connections
echo -e "configure network interfaces \n"
# net1
onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$net1`
proto=`grep BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-$net1`
sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$net1
sed -i 's/'$proto'/BOOTPROTO=static/' /etc/sysconfig/network-scripts/ifcfg-$net1
sed -i '/BOOTPROTO=static/a \IPADDR='$ip_addr' \nNETMASK='$net_mask'' /etc/sysconfig/network-scripts/ifcfg-$net1
# sed -i 's/DEFROUTE="yes"/DEFROUTE=no/' /etc/sysconfig/network-scripts/ifcfg-$net1
sleep 1
echo -e "done configure $net1 \n"

# net2
onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$net2`
sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$net2
sleep 1
echo -e "done configure $net2 \n"

# net3 
onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$net3`
proto=`grep BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-$net3`
sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$net3
if [ "$proto" == "" ]
then
  echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-$net3
else
  sed -i 's/'$proto'/BOOTPROTO=none/' /etc/sysconfig/network-scripts/ifcfg-$net3
fi
sleep 1
echo -e "done configure $net3 \n"

# net4
onboot=`grep ONBOOT /etc/sysconfig/network-scripts/ifcfg-$net4`
proto=`grep BOOTPROTO /etc/sysconfig/network-scripts/ifcfg-$net4`
sed -i 's/'$onboot'/ONBOOT=yes/' /etc/sysconfig/network-scripts/ifcfg-$net4
if [ "$proto" == "" ]
then
  echo "BOOTPROTO=none" >> /etc/sysconfig/network-scripts/ifcfg-$net3
else
    sed -i 's/'$proto'/BOOTPROTO=none/' /etc/sysconfig/network-scripts/ifcfg-$net3
fi

sleep 1
echo -e "done configure $net4 \n"

# restart network
systemctl restart NetworkManager.service
sleep 1

# looks like it is need to shutdown net1, otherwise it will take default gateway away and cause no access to internet for remaining work
# Note that net1 is not needed for the remaining scripts until after reboot 
# ifdown $net1
sleep 5
echo -e "done network config \n"

# determine the proxy servers
if [ -n "$ONPS_HTTP_PROXY" ]
then
  my_http_proxy=$ONPS_HTTP_PROXY;
  if [ -n "$ONPS_HTTP_PROXY_PORT" ]
  then
    my_http_proxy="$ONPS_HTTP_PROXY:$ONPS_HTTP_PROXY_PORT"
  fi
fi

if [ -n "$ONPS_HTTPS_PROXY" ]
then
  my_https_proxy=$ONPS_HTTPS_PROXY;
  if [ -n "$ONPS_HTTPS_PROXY_PORT" ]
  then
    my_https_proxy="$ONPS_HTTPS_PROXY:$ONPS_HTTPS_PROXY_PORT"
  fi
fi

# configure proxy and no_proxy for http, https and ftp 
echo -e "configure proxy settings \n"
if [ -n "$my_http_proxy" ]
then
  echo "export http_proxy=$my_http_proxy" >> /root/.bashrc
  echo "proxy=http://$my_http_proxy" >> /etc/yum.conf
fi

if [ -n "$my_https_proxy" ]
then
  echo "export https_proxy=$my_https_proxy" >> /root/.bashrc
fi

if [ -n "$NO_PROXY" ]
then
  echo "export no_proxy=localhost,$ip_addr,$NO_PROXY" >> /root/.bashrc
fi
sleep 1

# source .bashrc
source /root/.bashrc
sleep 1
echo -e "done http, https, ftp, yum proxy configurations \n"

# if choose using specific kernel version or use in-box kernel, need to lock the kernel, otherwise yum update will upgrade kernel 
if [ $kernel_to_use != "latest" ] 
then
  echo "exclude=kernel*" >> /etc/yum.conf
fi
sleep 2
echo -e "done yum configuration\n"

# configure git 
# install git package
echo -e "configure git  \n"
yum install -y git
sleep 1
echo -e "done installing git packages \n"

if [ -n "$ONPS_HTTP_PROXY" ]
then
  # create gitconnect in /usr/local/bin
  echo 'exec socat STDIO SOCKS4:onps_http_proxy:$1:$2' > /usr/local/bin/gitconnect
  sed -i "s/SOCKS4:onps_http_proxy/SOCKS4:$ONPS_HTTP_PROXY/" /usr/local/bin/gitconnect
  chmod +x /usr/local/bin/gitconnect

  # set git proxy, create and edit .gitconfig
  echo "[http]" > /root/.gitconfig
  echo "    proxy = $my_http_proxy" >> /root/.gitconfig

  if [ -n "$my_https_proxy" ]
  then
    echo "[https]" >> /root/.gitconfig
    echo "    proxy = $my_https_proxy" >> /root/.gitconfig
  fi

  echo "[core]" >> /root/.gitconfig
  if [ -n "$NO_GIT_PROXY" ]
  then
    echo "    gitproxy = none for $NO_GIT_PROXY" >> /root/.gitconfig
  fi
  echo "    gitproxy = /usr/local/bin/gitconnect" >> /root/.gitconfig
  sleep 1
fi
echo -e "done git configuration \n"

# install ntp
echo -e "install NTP  \n"
yum install -y ntp
sleep 1
echo -e "done installing ntp packages \n"

# configure ntp server
echo "server $ntp_server_name" >> /etc/ntp.conf
sed -i 's/server 0.fedora.pool.ntp.org iburst/#server 0.fedora.pool.ntp.org iburst/g' /etc/ntp.conf
sed -i 's/server 1.fedora.pool.ntp.org iburst/#server 1.fedora.pool.ntp.org iburst/g' /etc/ntp.conf
sed -i 's/server 2.fedora.pool.ntp.org iburst/#server 2.fedora.pool.ntp.org iburst/g' /etc/ntp.conf
sed -i 's/server 3.fedora.pool.ntp.org iburst/#server 3.fedora.pool.ntp.org iburst/g' /etc/ntp.conf
sleep 1
echo "done NTP configuration \n"

# install necessary yum packages for openstack use
echo "install necessary packages \n"
# packages need for ONP standard OS installation
yum install -y patch socat libxslt-devel libffi-devel fuse-devel glusterfs  
sleep 1

# user preference packages here (not required)
yum install -y vim-minimal vim
sleep 1
echo -e "done yum package installation \n"


# disable/enable services for openstack 
echo -e "enable/disable services for openstack needs \n" 
# set selinux to permissive mode
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sleep 1

# disable firewalld
systemctl stop firewalld.service
systemctl disable firewalld.service
sleep 1

# disable Networkmanager
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service
sleep 1

# enable network service
chkconfig network on
sleep 1

# enable ntpd
systemctl start ntpd.service
systemctl enable ntpd.service
sleep 1

# enable sshd
systemctl start sshd.service
systemctl enable sshd.service
sleep 1
echo -e "done service configuration \n"

# update timing against ntp server
ntpdate -u $ntp_server_name
sleep 1
echo -e "done sync timing \n"


# edit /etc/libvirt/qemu.conf for DPDK if this is a compute node
# Note: huge page mount point is /mnt/huge
shopt -s nocasematch
if [ "$node_type" == "compute" ]
then
  echo -e "configure libvirt for DPDK needs \n "
  echo 'cgroup_controllers = [ "cpu", "devices", "memory", "blkio", "cpuset", "cpuacct" ]' >> /etc/libvirt/qemu.conf
  echo 'cgroup_device_acl = [' >> /etc/libvirt/qemu.conf
  echo '    "/dev/null", "/dev/full", "/dev/zero",' >> /etc/libvirt/qemu.conf
  echo '    "/dev/random", "/dev/urandom",' >> /etc/libvirt/qemu.conf
  echo '    "/dev/ptmx", "/dev/kvm", "/dev/kqemu",' >> /etc/libvirt/qemu.conf
  echo '    "/dev/rtc", "/dev/hpet", "/dev/net/tun"]' >> /etc/libvirt/qemu.conf
  sleep 1

  if [ "$ovs_type" == "ovs-dpdk" ]
  then
    sed -i 's/tun\"\]/tun\"\,/g' /etc/libvirt/qemu.conf
    echo '    "/mnt/huge","/dev/vhost-net"]' >> /etc/libvirt/qemu.conf

    echo 'hugetlbfs_mount = "/mnt/huge"' >> /etc/libvirt/qemu.conf
  fi

  systemctl restart libvirtd.service
  echo -e "done updating /etc/libvirt/qeum.conf \n"
  sleep 1
fi
shopt -u nocasematch


# if choose using specific kernel, need to download and install rpm packages 
# otherwise run yum update to get the latest kernel 
if [ $kernel_to_use == "specific" ]
then  
  # download kernel $version  packages and install
  echo -e "download kernel $version  \n"
  wget $kernelURL/kernel-core-$version.rpm
  wget $kernelURL/kernel-modules-$version.rpm
  wget $kernelURL/kernel-$version.rpm
  wget $kernelURL/kernel-devel-$version.rpm
  wget $kernelURL/kernel-modules-extra-$version.rpm
  sleep 1
  echo -e "done kernel $version downloads  \n"

  # install $version kernel
  echo -e "installing  kernel $version  \n"
  rpm -i kernel-core-$version.rpm
  rpm -i kernel-modules-$version.rpm
  rpm -i kernel-$version.rpm
  rpm -i kernel-devel-$version.rpm
  rpm -i kernel-modules-extra-$version.rpm
  sleep 1
  echo -e "done kernel $version install  \n"
fi

# if choose using realtime kernel, need to clone source, compile, and install 
if [ $kernel_to_use == "realtime" ]
then
  echo -e "install realtime kernel \n"
  realtime_kernel_version=$version

  # install necessary package
  echo -e "install ncurses module \n"
  yum install ncurses-devel -y
  echo -e "done installing ncurses-devel "
  sleep 1

  # download kernel source from kernel.org
  echo -e "download kernel source  \n"
  cd /usr/src/kernels
  git clone $kernelURL 
  echo -e "done downloading kernel source  \n"
  sleep 2

  # checkout to RT kernel
  cd linux-stable-rt
  git checkout $realtime_kernel_version
  echo -e "check to $realtime_kernel_version kernel  \n"
  sleep 1

  # create .config file using existing kernel .config file
  cp /usr/src/kernels/`uname -r`/.config .config
  yes "" | make oldconfig
  echo -e "done copying and make oldconfig to $realtime_kernel_version  \n"
  sleep 1
  
  # config and set to premptible RT 
  sed -i 's/# CONFIG_PREEMPT_RT_FULL is not set/CONFIG_PREEMPT_RT_FULL=yes/g' .config

  # comment out this module - it gave error when doing make install
  sed -i 's/CONFIG_BT_HCIVHCI=m/# CONFIG_BT_HCIVHCI/g' .config

  # need to make oldfconfig again
  yes "" | make oldconfig
  echo -e "done .config file  \n"
  sleep 1
   
  # make and install new kernel
  make -j `grep -c processor /proc/cpuinfo`
  echo -e "done make  \n"
  sleep 1

  make modules_install
  echo -e "done make modules install  \n"
  sleep 1

  make install
  echo -e "done kernel install  \n"
  sleep 1

  #change boot order 
  grub2-set-default "`grep menuentry /boot/grub2/grub.cfg | grep "Twenty" | cut -d"'" -f2`"
fi


# Now working with user 'stack'
#    Note: 'stack' is already created during OS installation
# ======================================
echo -e "stack user configurations \n" 
# add 'stack' to sudoer
echo "stack ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
sleep 1
echo -e "done adding sudoer for stack user \n"

# find internet network ip address
inet_ip=`ifconfig $net2 | grep netmask | awk '{print $2}'`
sleep 1 

# set stack user proxy, edit /home/stack/.bashrc and apply to env
if [ -n "$my_http_proxy" ]
then
  echo "export http_proxy=$my_http_proxy" >> /home/stack/.bashrc
fi

if [ -n "$my_https_proxy" ]
then
  echo "export https_proxy=$my_https_proxy" >> /home/stack/.bashrc
fi

echo "export no_proxy=localhost,$host_name,$ip_addr,$inet_ip,$controller_name,$controller_ip,$NO_PROXY" >> /home/stack/.bashrc
sleep 2
echo -e "done proxy for stack user \n"

# set stack user git proxy
if [ -n "$my_http_proxy" ]
then
  echo "[http]" > /home/stack/.gitconfig
  echo "    proxy = $my_http_proxy" >> /home/stack/.gitconfig

  if [ -n "$my_https_proxy" ]
  then
    echo "[https]" >> /home/stack/.gitconfig
    echo "    proxy = $my_https_proxy" >> /home/stack/.gitconfig
  fi

  echo "[core]" >> /home/stack/.gitconfig
  if [ -n "$NO_GIT_PROXY" ]
  then
    echo "    gitproxy = none for $NO_GIT_PROXY" >> /home/stack/.gitconfig
  fi

  echo "    gitproxy = /usr/local/bin/gitconnect" >> /home/stack/.gitconfig

  chown stack:stack /home/stack/.gitconfig
fi
echo -e "done git proxy for stack user \n"


# write option whether to use commit ids for devstack components
echo "configure whether using commit ids or using latest codes " 
if [ -n "$use_commit_id" ]
then
  sed -i 's/use_commit_id=/use_commit_id='$use_commit_id'/g' $file_path/prepare_stack.sh
  sleep 1
fi

echo "copy prepare_stack.sh to /home/stack/" 
cp $file_path/prepare_stack.sh /home/stack/
cp $file_path/onps_commit_ids /home/stack/
chown stack:stack /home/stack/prepare_stack.sh
chown stack:stack /home/stack/onps_commit_ids
sleep 1
echo -e "done prepare_stack script \n"

# create local.conf file 
shopt -s nocasematch
if [ $node_type == "controller" ]
then
  cp $file_path/local.conf-controller /home/stack/local.conf
  sleep 1

  sed -i 's/HOST_IP=/HOST_IP='$ip_addr'/g' /home/stack/local.conf
  sed -i 's/HOST_IP_IFACE=/HOST_IP_IFACE='$net1'/g' /home/stack/local.conf
  sed -i 's/PUBLIC_INTERFACE=/PUBLIC_INTERFACE='$net4'/g' /home/stack/local.conf
  sed -i 's/VLAN_INTERFACE=/VLAN_INTERFACE='$net3'/g' /home/stack/local.conf
  sed -i 's/FLAT_INTERFACE=/FLAT_INTERFACE='$net3'/g' /home/stack/local.conf
  sed -i 's/OVS_PHYSICAL_BRIDGE=/OVS_PHYSICAL_BRIDGE=br-'$net3'/g' /home/stack/local.conf
elif  [ $node_type == "compute" ]
then
  cp $file_path/local.conf-compute /home/stack/local.conf
  sleep 1

  sed -i 's/OVS_TYPE=/OVS_TYPE='$ovs_type'/g' /home/stack/local.conf
  sed -i 's/HOST_IP=/HOST_IP='$ip_addr'/g' /home/stack/local.conf
  sed -i 's/vncserver_proxyclient_address=/vncserver_proxyclient_address='$ip_addr'/g' /home/stack/local.conf
  sed -i 's/HOST_IP_IFACE=/HOST_IP_IFACE='$net1'/g' /home/stack/local.conf
  sed -i 's/SERVICE_HOST_NAME=/SERVICE_HOST_NAME='$controller_ip'/g' /home/stack/local.conf
  sed -i 's/SERVICE_HOST=/SERVICE_HOST='$controller_ip'/g' /home/stack/local.conf
  sed -i 's/OVS_PHYSICAL_BRIDGE=/OVS_PHYSICAL_BRIDGE=br-'$net3'/g' /home/stack/local.conf

  # for compute node, no need to populate these services
  sed -i 's/glance git/#glance git/g' /home/stack/onps_commit_ids
  sed -i 's/keystone git/#keystone git/g' /home/stack/onps_commit_ids
  sed -i 's/horizon git/#horizon git/g' /home/stack/onps_commit_ids
  sed -i 's/cinder git/#cinder git/g' /home/stack/onps_commit_ids
  sed -i 's/tempest git/#tempest git/g' /home/stack/onps_commit_ids
  sed -i 's/noVNC https/#noVNC https/g' /home/stack/onps_commit_ids

  if [ $ovs_type == "ovs" ]
  then
    sed -i 's/Q_AGENT=/Q_AGENT=openvswitch/g' /home/stack/local.conf

  elif [ $ovs_type == "ovs-dpdk" ]
  then
    sed -i 's/Q_AGENT=/OVS_AGENT_TYPE=openvswitch/g' /home/stack/local.conf
    sed -i '/Q_ML2_PLUGIN_TYPE_DRIVERS/a \OVS_GIT_TAG='$ovs_git_tag' \nOVS_DPDK_GIT_TAG='$ovs_dpdk_git_tag' \nOVS_DATAPATH_TYPE='$ovs_datapath_type'' /home/stack/local.conf
    sed -i '/OVS_DATAPATH_TYPE/a \OVS_NUM_HUGEPAGES=8192 \nOVS_DPDK_MEM_SEGMENTS=8192 \nOVS_HUGEPAGE_MOUNT_PAGESIZE=2M' /home/stack/local.conf
    sed -i 's/Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch/Q_ML2_PLUGIN_MECHANISM_DRIVERS=openvswitch,ovsdpdk/g' /home/stack/local.conf
    sed -i '/enable_service q-agt/a \enable_plugin networking-ovs-dpdk https://github.com/stackforge/networking-ovs-dpdk 2015.1 \nOVS_DPDK_RTE_LIBRTE_VHOST=n' /home/stack/local.conf
  fi
fi
sleep 1
shopt -u nocasematch

chown stack:stack /home/stack/local.conf
sleep 1
echo -e "done creating local.conf file \n"

# done system preparations
echo -e "done fedora system preparations \n"
echo -e "next steps: \n"
echo -e "    1. reboot the system \n"
echo -e "    2. login as root, run command 'yum update -y',  then reboot again \n"
echo -e "    3. login as stack \n"
echo -e "    4. run script 'prepare_stack.sh' to install openstack\n"
echo

exit 1

