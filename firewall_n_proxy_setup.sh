#!/bin/bash

# To simulate corportae env with fireall we have this script
# if variable DO_USE_PROXY == true, a filreawll will be configured and proxy allowed to access internet

DO_USE_PROXY=${DO_USE_PROXY:-true}

echo Initializing proxy and firewall
HOSTNAME=$(hostname -s)
PORTS_TO_CLOSE="80 443"

if [[ ${HOSTNAME} != "proxy-lb" ]]; then
  grep -qF DO_USE_PROXY /home/k8s/.bashrc
  if [[ $? != "0" ]]; then    
    echo "export DO_USE_PROXY=${DO_USE_PROXY}" >>/home/k8s/.bashrc
  fi
fi

if [[ ${DO_USE_PROXY} == "true" ]]; then
  if [[ ${HOSTNAME} != "proxy-lb" ]]; then
    # activate firewall on k8s nodes using nft, set enc variables

    grep -Fq proxy-lb /etc/dnf/dnf.conf
    if [[ $? != "0" ]]; then
      echo >>/etc/dnf/dnf.conf
      echo "# added by $0" >>/etc/dnf/dnf.conf
      echo "proxy=http://proxy-lb:3128" >>/etc/dnf/dnf.conf
    fi

    # check for firewalld table in nft
    # this is not clean solution - perhaps k8s change nft structure and this will stop work
    nft list tables | grep -q filter
    if [[ $? == "0" ]]; then
      echo Flushing nft tables
      nft flush ruleset
    fi

    echo nft not initialized, initilizing
    nft add table inet filter || exit 1
    nft add chain inet filter output { type filter hook output priority 0\; } || exit 1
    for a_port in ${PORTS_TO_CLOSE}
    do
      nft add rule inet filter output ip protocol tcp tcp dport ${a_port} log prefix \"BLOCK_${a_port}_OUT: \" flags all counter || exit 1
      nft add rule inet filter output ip protocol tcp tcp dport ${a_port} reject || exit 1
    done

    systemctl enable --now nftables || exit 1
    systemctl is-active nftables || exit 1

    echo Testing firewall ...
    nc -z -w1 www.sme.sk 443
    if [[ $? == "0" ]]; then
      echo $0 error: firewall setting does not work, fix me, DO_USE_PROXY=${DO_USE_PROXY} >&2
      echo $0 info: failed command was: nc -z -w1 www.sme.sk 443 >&2
      exit 1
    fi
    echo Outbount connect to 443, are blocked, check /var/log/messages to debug
    # 2025-08-09: saving nftables, we believe, it will bre reloadin on reboot each time
    nft list ruleset > /etc/nftables/firewall-for-web-k8s-lab.nft 2>/dev/null
  else
    dnf -y install squid || exit 1
    # change form of logs
    grep -Fq human_time /etc/squid/squid.conf
    if [[ $? != "0" ]]; then
      echo 'logformat human_time %tl %6tr %>a %Ss/%03>Hs %<st %rm %ru %un %Sh/%<a %mt' >>/etc/squid/squid.conf
      echo 'access_log /var/log/squid/access.log human_time' >>/etc/squid/squid.conf
    fi
    systemctl enable --now squid || exit 1
    # a few seconds to wait to squid wake up
    sleep 5
  fi


  CLUSTER_NODE_LIST=$(grep 10. /etc/hosts |awk '{print $2}'| grep -v proxy-lb |xargs | tr ' ' ,)
  grep -Fq proxy-lb /root/.bashrc
  if [[ $? != "0" ]]; then
    echo "export HTTP_PROXY=http://proxy-lb:3128" >>/root/.bashrc
    echo "export HTTPS_PROXY=http://proxy-lb:3128" >>/root/.bashrc
    echo "export NO_PROXY=localhost,10.0.0.0/8,192.168.0.0/16,127.0.0.0/8,${CLUSTER_NODE_LIST}" >>/root/.bashrc
  fi
  K8S_HOME=$(getent passwd k8s | cut -d: -f6)
  grep -Fq proxy-lb ${K8S_HOME}/.bashrc
  if [[ $? != "0" ]]; then
    echo "export HTTP_PROXY=http://proxy-lb:3128" >>${K8S_HOME}/.bashrc
    echo "export HTTPS_PROXY=http://proxy-lb:3128" >>${K8S_HOME}/.bashrc
    echo "export NO_PROXY=localhost,10.0.0.0/8,192.168.0.0/16,127.0.0.0/8,${CLUSTER_NODE_LIST}" >>${K8S_HOME}/.bashrc
  fi
else
    # proxy is not used, direct connect to internet
    echo DO_USE_PROXY != true - no special setup on any node
fi

echo Proxy and firewall configured
exit 0