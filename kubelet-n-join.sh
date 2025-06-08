#!/bin/bash

echo Starting service if not running
HOSTNAME=$(hostname -s)

# no action on proxy
test ${HOSTNAME} == "proxy-lb" && exit 0

# allnodes other nodes
systemctl enable --now kubelet
sleep 3

cnt=10
while :
do
  systemctl is-active --quiet kubelet.service && break
  if [[ ${cnt} == 0 ]]; then
    echo $0 error: Unable to start kubelet service on host ${HOSTNAME} >&2
    exit 1
  fi
  sleep 6
  let cnt-=1
done
test $? != "0" && exit 1
echo Service kubelet running on ${HOSTNAME}


echo Joining new nodes to cluster
if [[ ${HOSTNAME} == node* ]]; then
  if [[ -f /tmp/k8s.join ]]; then 
    bash /tmp/k8s.join || exit 1
    rm -f /tmp/k8s.join
  fi
fi

echo Services runngin workers joined
exit 0