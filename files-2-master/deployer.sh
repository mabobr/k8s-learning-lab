#!/bin/bash

#####################################################################
# MB this will deploy variao k8s mabifests based on env variables
DEP_ADD_PERSISTENT_VOLUME=${DEP_ADD_PERSISTENT_VOLUME:-false}
#####################################################################

DEPLOYMENTS_DIR=${HOME}/deployments

if [[ ${USER} != "k8s" ]]; then
  echo $0 error: bad user >&2
  exit 1
fi
HOSTNAME=$(hostname -s)
if [[ ${HOSTNAME} != 'master' ]]; then
  echo $0 error: bad host >&2
  exit 1
fi

cd ${DEPLOYMENTS_DIR} || exit 1

if [[ ${DEP_ADD_PERSISTENT_VOLUME} == 'true' ]]; then
  kubectl destroy nfs-persistent-volume
  kubectl apply -f ./persistent-volume-on-nfs.yaml || exit 1
  kubectl get pv
fi

exit 0