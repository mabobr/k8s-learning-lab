#!/bin/bash 

echo Preparing instaling and initilizing k8s
HOSTNAME=$(hostname -s)

if [[ ${HOSTNAME} != "proxy-lb" ]]; then

fi
echo k8s installed and initialized
exit 0