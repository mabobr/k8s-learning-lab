#!/bin/bash

echo Generic common system setup RHEL9

HOSTNAME=$(hostname -s)
timedatectl set-timezone Europe/Bratislava
localectl set-locale LC_TIME=en_GB.UTF-8

# tcpdump - for debug purposes - remove them
dnf -y install firewalld nftables net-tools nc tmux emacs-nox nfs-utils tcpdump || exit 1

# we will use nftables only 
systemctl disable firewalld >/dev/null 2>/dev/null
systemctl mask --now firewalld
systemctl enable --now nftables
#systemctl enable --now firewalld || exit 1

# setup NFT filters
# nft add table inet filter || exit 1
# nft add chain inet filter input { type filter hook input priority filter \\; } || exit 1
# nft add chain inet filter forward { type filter hook forward priority filter \\; } || exit 1
# nft add chain inet filter output { type filter hook output priority filter \\; } || exit 1
# grep -q '22 accept' /etc/sysconfig/nftables.conf
# if [ $? != "0" ] ; then
#     nft add rule inet filter input tcp dport 22 accept || exit 1
# fi

# nft add chain inet filter input '{ policy drop; }'
# echo "flush ruleset" > /etc/sysconfig/nftables.conf
# nft list ruleset >> /etc/sysconfig/nftables.conf

dnf -y update

# each node will have installed falco security 
if [[ ${DO_INCLUDE_FALCO} == "true" ]] ; then
  echo "Configureing FALCO"
  if [[ ${HOSTNAME} == "node0" || ${HOSTNAME} == "node1" ]] ; then
    echo Installing falco security module
    dnf config-manager --set-enabled crb || exit 1
    dnf install -y epel-release || exit 1
    dnf install -y dkms make || exit 1
    dnf install -y kernel-devel || exit 1
    dnf install -y clang llvm || exit 1
    dnf install -y dialog || exit 1

    rpm --import https://falco.org/repo/falcosecurity-packages.asc || exit 1
    curl -s -o /etc/yum.repos.d/falcosecurity.repo https://falco.org/repo/falcosecurity-rpm.repo
    dnf update -y || exit 1
    dnf install -y falco || exit 1
  fi
else
  echo FALCO not required
fi

echo Setting up k8s DNS

echo >>/etc/hosts
echo # Following added by $0 >>/etc/hosts
echo 10.10.10.10 master >>/etc/hosts
echo 10.10.10.20 node0  >>/etc/hosts
echo 10.10.10.21 node1  >>/etc/hosts
echo 10.10.10.99 proxy-lb >>/etc/hosts

# k8s - does not like selinux, perhaps in far future, we can enable and test ...
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
# swap off
if [[ ${HOSTNAME} != "proxy-lb" ]]; then
  swapoff -a || exit 1
  sed -e '/swap/s/^/#/g' -i /etc/fstab || exit 1
fi

echo rhel9_setup_sh setup DONE OK, SElinux disabled, reboot will follow
exit 0