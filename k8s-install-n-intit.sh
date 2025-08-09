#!/bin/bash 

echo Preparing instaling and initilizing k8s
HOSTNAME=$(hostname -s)

K8S_VERSION=${K8S_VERSION:-1.33}

if [[ ${HOSTNAME} != "proxy-lb" ]]; then
  if [[ -z ${POD_NETWORK_CIDR} ]] ; then
    echo $0 error: Value for POD_NETWORK_CIDR not set >&2
    exit 1
  fi    

  echo USING POD_NETWORK_CIDR=${POD_NETWORK_CIDR}

  #Create a configuration file for containerd:
  if [[ ! -f /etc/modules-load.d/containerd.conf ]]; then
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

    modprobe overlay || exit 1
    modprobe br_netfilter || exit 1
  fi

  if [[ ! -f /etc/sysctl.d/99-kubernetes-cri.conf ]]; then
    #Set system configurations for Kubernetes networking:
    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
  fi
  sysctl -q --system

  echo Setup for containerd ...
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || exit 1
  dnf -y makecache || exit 1
  dnf install -y containerd.io curl git || exit 1
  # backup default config
  if [[ ! -f /etc/containerd/config.toml.bak ]]; then
    mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
    containerd config default > /etc/containerd/config.toml || exit 1
    sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml || exit 1

    if [[ ${DO_USE_PROXY} == "true" ]]; then
      # if using proxy, configure env
      echo Configuring containerd to use http proxy
      mkdir -p /etc/systemd/system/containerd.service.d || exit 1
      cat <<EOF | sudo tee /etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://proxy-lb:3128"
Environment="HTTPS_PROXY=http://proxy-lb:3128"
Environment="NO_PROXY=localhost,10.0.0.0/8,192.168.0.0/16,127.0.0.0/8"
EOF
    fi

    systemctl daemon-reload || exit 1
    systemctl enable --now containerd.service || exit 1
  fi
  sleep 3
  systemctl is-active --quiet containerd.service || exit 1

  echo Preparing kublelet
  if [ ! -f /etc/yum.repos.d/kubernetes.repo ] ; then
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

    dnf -y makecache || exit 1
    dnf -y install kubelet kubeadm kubectl --disableexcludes=kubernetes || exit 1
    systemctl enable kubelet.service
  fi

  # no service is being started no, but on master, we initialize k8s
  if [[ ${HOSTNAME} = "master" ]]; then
    if [[ ! -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] ; then
      DEFAULT_DEV=$(netstat -rn|grep "^0.0.0.0" |awk '{print $8}')
      if [[ -z ${DEFAULT_DEV} ]] ; then
        echo $0 error: DEFAULT_DEV not found, check command: netstat -rn >&2
        exit 1
      fi

      MY_IP=$(ifconfig ${DEFAULT_DEV} | grep "broadcast" | awk '{print $2}')
      #--apiserver-advertise-address is ip of dedicated master ip, using hardcoded 10.10.10.10
      K8S_API_IP=10.10.10.10
      echo EXEC: kubeadm init --pod-network-cidr ${POD_NETWORK_CIDR}  --apiserver-advertise-address=${K8S_API_IP} --control-plane-endpoint=master
      kubeadm init --pod-network-cidr ${POD_NETWORK_CIDR} --apiserver-advertise-address=${K8S_API_IP} --control-plane-endpoint=master || exit 1

      K8S_HOME=$(getent passwd k8s | cut -d: -f6)
      mkdir -p ${K8S_HOME}/.kube || exit 1
      cp -i /etc/kubernetes/admin.conf $K8S_HOME/.kube/config || exit 1
      echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >>/root/.bashrc
      chown -R k8s:k8s $K8S_HOME/.kube || exit 1

      # creating and distributing join command
      kubeadm token create --print-join-command >/tmp/k8s.join
      cat /etc/hosts | grep node| awk '{print $2}' | while read NODE
      do
        # nasty simplification accesing k8s key
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /home/k8s/.ssh/k8s.key /tmp/k8s.join k8s@${NODE}:/tmp/k8s.join || exit 1
      done
      test $? != "0" && exit 1
      rm -f /tmp/k8s.join
      echo Join command distributed
    else
      echo k8s is already initialized, when re-initialization is needed, destroy VMs via vagrant
    fi
    mkdir -p --mode 1777 /tmp/k8s.d || exit 1
  fi
fi
echo k8s installed and initialized
exit 0