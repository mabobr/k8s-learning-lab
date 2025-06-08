#!/bin/bash

echo Preparing app account k8s
HOSTNAME=$(hostname -s)

grep -q "^k8s:" /etc/passwd
if [[ $? != "0" ]] ; then
  useradd -c "apl. k8s user" k8s || exit 1
  K8S_HOME=$( getent passwd k8s | cut -d: -f6 )
fi
K8S_HOME=$( getent passwd k8s | cut -d: -f6 )
grep -qF sr/local/bi ${K8S_HOME}/.bashrc
if [[ $? != "0" ]]; then
  echo "export PATH=${PATH}:/usr/local/bin" >>${K8S_HOME}/.bashrc
fi

if [[ ! -d ${K8S_HOME}/.ssh ]] ; then
  mkdir -p ${K8S_HOME}/.ssh || exit 1
fi
if [[ -f /tmp/k8s.key ]] ; then
  mv /tmp/k8s.key ${K8S_HOME}/.ssh || exit 1
fi
if [[ -f /tmp/k8s.key.pub ]] ; then
  cat /tmp/k8s.key.pub >${K8S_HOME}/.ssh/authorized_keys
  rm -f /tmp/k8s.key.pub
fi

chown -R k8s:k8s ${K8S_HOME}/.ssh || exit 1
chmod 700 ${K8S_HOME}/.ssh || exit 1
chmod 600 ${K8S_HOME}/.ssh/k8s.key ${K8S_HOME}/.ssh/authorized_keys || exit 1

if [[ ${HOSTNAME} == "proxy-lb" ]]; then
  # we need this user to manage nginx (LB) service, for simplification, will be given root sudo
  if [[ ! -f /etc/sudoers.d/k8s-to-root ]]; then
    echo "k8s  ALL=(ALL)       NOPASSWD: ALL" >/etc/sudoers.d/k8s-to-root
  fi
fi

echo App account k8s ready
exit 0