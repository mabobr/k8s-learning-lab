#!/bin/bash 
#env
# final E2E check

echo Final E2E check staring
HOSTNAME=$(hostname -s)

# ssh connect to each node
while read NODE
do
  nc -z -w1 ${NODE} 22
  if [[ $? != "0" ]]; then
    echo $0 error: unable to connect to ${NODE}:22 test failed >&2
    exit 1
  fi
done < <(grep "^10." /etc/hosts | awk '{print $2}')
echo Each host connectable on port 22

if [[ ${DO_USE_PROXY} == "true" ]]; then
  if [[ ${HOSTNAME} != "proxy-lb" ]]; then
    nc -z -w1 www.sme.sk 443
    if [[ $? == "0" ]]; then
      echo $0 error: DO_USE_PROXY==true but firewall is not activated, connect to www.sme.sk:443 allowed, test failed
      exit 1
    fi
    echo Firewall on ${HOSTNAME} is active
  fi
fi

# are important service running
if [[ ${HOSTNAME} != "proxy-lb" ]]; then
  for a_svc in containerd.service kubelet.service
  do
    echo Testing status of ${a_svc}
    systemctl is-active --quiet ${a_svc}
    if [[ $? != "0" ]]; then
      echo $0 error: service ${a_svc} is not active >&2
      exit 1
    fi
  done
  test $? != "0" && exit $?
else
  if [[ ${DO_USE_PROXY} == "true" ]]; then
    echo Testing status of squid.service
    systemctl is-active --quiet squid.service
    if [[ $? != "0" ]]; then
      echo $0 error: service squid.service is not active >&2
      exit 1
    fi
  fi
fi

if [[ ${HOSTNAME} == node* ]]; then
  TXT=$(cat /nfs/master/test_file 2>/dev/null)
  if [[ ${TXT} != "NFS works" ]]; then
    echo $0 error: Unable to read data from NFS share >&2
    exit 1
  fi
  echo NFS service tested OK
fi

if [[ ${HOSTNAME} == "master" ]]; then
  kubectl get nodes
fi

echo Final E2E check OK
exit 0