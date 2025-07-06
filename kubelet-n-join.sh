#!/bin/bash

echo Starting service if not running
HOSTNAME=$(hostname -s)
. ${HOME}/.bashrc

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
    echo Serring role of node to worker
  else
    echo join command not found, assuming, already joinned
  fi
elif [[ ${HOSTNAME} == "master" ]]; then
  echo Installing calico CNI

  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml || exit 1        
  echo Waiting for cluster to become ready, waiting for 3 ready nodes, max 5 min
  let TTL=$(date +%s)+300
  while :
  do
    CNT=$(kubectl get nodes | grep ' Ready ' | wc -l)
    if [ $CNT -eq 3 ] ; then
      break
    fi
    if [ $(date +%s) -gt ${TTL} ] ; then
      echo $0 error: Cluster not ready in 5 minutes, check: kubectl get nodes >&2
      exit 1
    fi
    sleep 17
    echo $(date)" Still waiting ... CNT=${CNT}"
  done
  test $? != "0" && exit 1

  grep -F node /etc/hosts |awk '{print $2}' | while read NODENAME
  do
    kubectl label node ${NODENAME} node-role.kubernetes.io/worker=worker || exit 1
    echo Node ${NODENAME} labeled as worker
  done
fi

echo Services running workers joined
exit 0