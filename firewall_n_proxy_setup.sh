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
    # activate firewall on k8s nodes usoing nft, set enc variables

    grep -Fq proxy-lb /etc/dnf/dnf.conf
    if [[ $? != "0" ]]; then
      echo >>/etc/dnf/dnf.conf
      echo "# added by $0" >>/etc/dnf/dnf.conf
      echo "proxy=http://proxy-lb:3128" >>/etc/dnf/dnf.conf
    fi

    # check for firewalld table in nft
    # this is not clean solution - perhaps k8s change nft structure and this will stop work
    nft list tables | grep -q filter
    if [[ $? != "0" ]] ; then
      echo nft not initialized, initilizing
      nft add table inet filter || exit 1
      nft add chain inet filter output { type filter hook output priority 0\; } || exit 1
      for a_port in ${PORTS_TO_CLOSE}
      do
        nft add rule inet filter output ip protocol tcp tcp dport ${a_port} log prefix \"BLOCK_${a_port}_OUT: \" flags all counter || exit 1
        nft add rule inet filter output ip protocol tcp tcp dport ${a_port} reject || exit 1
      done

      systemctl enable --now nftables || exit 1
    fi
    test $? != "0" && exit 1

    echo Testing firewall ...
    nc -z -w1 www.sme.sk 443
    if [[ $? == "0" ]]; then
      echo $0 error: firewall setting does not work, fix me >&2
      exit 1
    fi
    echo Outbount connect to 443, are blocked, check /var/log/messages to debug
  else
    dnf -y install squid || exit 1
    # change form of logs
    grep -Fq human_time /etc/squid/squid.conf
    if [[ $? != "0" ]]; then
      echo 'logformat human_time %tl %6tr %>a %Ss/%03>Hs %<st %rm %ru %un %Sh/%<a %mt' >>/etc/squid/squid.conf
      echo 'access_log /var/log/squid/access.log human_time' >>/etc/squid/squid.conf
    fi
    systemctl enable --now squid || exit 1
    # a few seconds to wait to squild wake up
    sleep 5
  fi
else
    # proxy is not used, direct connect to internet
    echo DO_USE_PROXY != true - no special setup on any node
fi

echo Proxy and firewall configured
exit 0