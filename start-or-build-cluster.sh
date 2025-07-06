#!/bin/bash

# All configuration parameters to cluster are in Vagrantfile
VAGRANT_OPTIONS="--no-tty"

#####################################################
#  MAIN
#####################################################
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


if [[ ${EUID} == "0" ]] ; then
  echo $0 error: must not be root >&2
  exit 1
fi

STATUS=""
while read node_status
do
  if [[ -z ${STATUS} ]]; then
    STATUS=${node_status}
  else
    if [[ ${STATUS} != ${node_status} ]]; then
      echo $0 error: Cluster not in consistent status, fix manually, to check run: vagrant status >&2
      exit 1
    fi
  fi
done < <(vagrant status | grep -F '(libvirt)' | cut -f1 -d'(' | awk '{print $2,$3}')

if [[ ${STATUS} == "not created" ]]; then
  vagrant ${VAGRANT_OPTIONS} up --parallel --provision-with system-init,reload-after-update,copy-k8s-priv-key,copy-k8s-pub-key,prepare-k8s-account,firewall-n-proxy,setup_nfs-server || exit 1
  vagrant ${VAGRANT_OPTIONS} up --parallel --provision-with k8s-install-config,k8s-kubelet-n-join,mount-nfs || exit 1
elif [[ ${STATUS} == "running" ]]; then
  echo Cluster is running
elif [[ ${STATUS} == "shutoff" ]]; then
  vagrant ${VAGRANT_OPTIONS} up --parallel --provision-with firewall-n-proxy || exit 1
else
  echo $0 error: cluster in unknown, but consistent state: ${STATUS}, fix by hand >&2
  exit 1
fi

vagrant ${VAGRANT_OPTIONS} up --provision-with running_e2e_final_checks || exit 1

echo Cluster ready check local file SANS_Kubernetes_Cloud_Native_Security_DevSecOps_Automation.pdf
exit 0
