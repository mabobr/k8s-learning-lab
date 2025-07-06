#!/bin/bash

HOSTNAME=$(hostname -s)
. ${HOME}/.bashrc

test ${HOSTNAME} != "master" && exit 0

echo Initizing NFS on master

mkdir -p /nfs/{k8s,master} || exit 1
chown nobody:nobody /nfs/{k8s,master} || exit 1
chmod 777 /nfs/{k8s,master} || exit 1

rm -f /etc/exports
echo "/nfs/k8s      ${K8S_NETWORK_CIDR}(rw,sync,no_subtree_check)"   >/etc/exports
echo "/nfs/master   ${K8S_NETWORK_CIDR}(rw,sync,no_subtree_check)"   >>/etc/exports

systemctl enable --now nfs-server || exit 1
systemctl is-active nfs-server.service || exit 1
# firewall should be open
exportfs -ar || exit 1  

echo "NFS works" >/nfs/master/test_file
chmod 444 /nfs/master/test_file

echo NFS service should be ready, OK
exit 0