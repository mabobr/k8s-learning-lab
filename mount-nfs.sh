#!/bin/bash

HOSTNAME=$(hostname -s)
. ${HOME}/.bashrc

test ${HOSTNAME} == "master" && exit 0
test ${HOSTNAME} == "proxy-lb" && exit 0

mkdir -p /nfs/{k8s,master} || exit 1
chown nobody:nobody /nfs/{k8s,master} || exit 1
chmod 777 /nfs/{k8s,master} || exit 1

df -k | grep -q master:/nfs
if [[ $? != "0" ]] ; then
  echo Mounting NFS from master node on both worker nodes
  mount master:/nfs/master /nfs/master || exit 1
else
  echo NFS mounted
fi

echo NFS service mounted OK
exit 0