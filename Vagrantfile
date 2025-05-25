# -*- mode: ruby -*-
# vi: set ft=ruby :

# To build from scartch:
# vagrant up --parallel

############################################################################
# Variables to consider
############################################################################
# HW setup
mem_for_k8s_master = 4096
cpu_for_k8s_master = 2

# there are 2 of them (workers)
mem_for_k8s_worker = 4096
cpu_for_k8s_worker = 2

mem_for_support_vm = 4096
cpu_for_support_vm = 2

# FACLO is sec. too for kubernetes, default is false - it set to true - installation was not tested
DO_INCLUDE_FALCO="false"

# DO_USE_PROXY true or false
# if DO_USE_PROXY == true, an outbound  filrewall will be activated on all nodes, nodes are not able to 
# communucate to internet directly, ony via HTTP proxy, everything will be slow but secure ;)
DO_USE_PROXY="true"

############################################################################
# End od variables
############################################################################

############################################################################
# this VM runs squid as forward proxy to internet on port 3128
# and also nginx as LoadBalancer in front od k8s fo itls task
proxy_setup_sh = <<-SCRIPT
test $(hostname -s) != "proxy-lb" && exit 0

if [[ -f /tmp/nginx-mngr.sh ]] ; then
    mv /tmp/nginx-mngr.sh ${K8S_HOME} || exit 1
    chmod 750 ${K8S_HOME}/nginx-mngr.sh || exit 1
    chown k8s:k8s ${K8S_HOME}/nginx-mngr.sh || exit 1
fi

####################################################

dnf -y install nginx nginx-mod-stream || exit 1

# LoadBalander part - you may disable it, when LB is not used
# LB is required in, itls tests area
if [[ "1" == "1" ]] ; then

    if [[ -f /tmp/nginx-lb-ingress.conf ]] ; then
        mv /tmp/nginx-lb-ingress.conf /etc/nginx/nginx.conf.k8s
        chown nginx:nginx /etc/nginx/nginx.conf || exit 1
    else
        echo File /tmp/nginx-lb-ingress.conf not found
        exit 1
    fi

    systemctl list-unit-files | grep -q nginx
    if [ $? != "0" ] ; then
        echo $0 error: nginx not listes in systemd services
        exit 1
    fi
    systemctl is-active nginx.service >/dev/null
    if [[ $? != "0" ]] ; then
        systemctl enable --now nginx.service || exit 1
    else
        systemctl restart nginx.service || exit 1
    fi
    sleep 10
    systemctl is-active nginx.service || exit 1    

    # port 80 is for nodePort 81 is for plaintext ingress, 403 is for TLS ingress
    # outgoing port 443 is blocked 
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=81/tcp
    firewall-cmd --permanent --add-port=403/tcp
    firewall-cmd --reload    
    echo On proxy VM nginx is running w/ ports 80, 81, 403
fi
SCRIPT

############################################################################
# will setup k8s cluster to up&running state and create proxy 
app_init_sh = <<-SCRIPT
test $(hostname -s) == "proxy-lb" && exit 0

if [[ -z ${POD_NETWORK_CIDR} ]] ; then
    echo $0 error: Value for POD_NETWORK_CIDR not set >&2
    exit 1
fi

#env | sort
echo USING POD_NETWORK_CIDR=${POD_NETWORK_CIDR}

HOSTNAME=$(hostname -s)

# enabling firewall deny logs to debug network problems
sed -i "s/LogDenied=.*/LogDenied=all/" /etc/firewalld/firewalld.conf
systemctl reload firewalld

#Create a configuration file for containerd:
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay || exit 1
modprobe br_netfilter || exit 1

#Set system configurations for Kubernetes networking:
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl -q --system

####################################################
# selinux disable


# installing container.io
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || exit 1
dnf -y makecache || exit 1
dnf install -y containerd.io curl git || exit 1
# backup default config
mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
containerd config default > /etc/containerd/config.toml || exit 1
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml || exit 1

# if using proxy, configure env
echo Configuring containerd to use http proxy
mkdir -p /etc/systemd/system/containerd.service.d || exit 1
cat <<EOF | sudo tee /etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://proxy-lb:3128"
Environment="HTTPS_PROXY=http://proxy-lb:3128"
Environment="NO_PROXY=localhost,10.0.0.0/8,192.168.0.0/16,127.0.0.0/8"
EOF
systemctl daemon-reload

systemctl enable --now containerd.service || exit 1
systemctl status containerd.service

#####################################################
# installing
if [ ! -f /etc/yum.repos.d/kubernetes.repo ] ; then
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
fi

dnf -y makecache || exit 1
dnf -y install kubelet kubeadm kubectl --disableexcludes=kubernetes || exit 1
systemctl enable --now kubelet || exit 1

mkdir -p /nfs/{k8s,master}  || exit 1

if [[ ${HOSTNAME} = "master" ]] ; then
    # for k8s storage we will run NFS at master node
    
    chown nobody:nobody /nfs/{k8s,master} || exit 1
    chmod 777 /nfs/{k8s,master} || exit 1
    echo "/nfs/k8s      192.168.121.0/24(rw,sync,no_subtree_check)"   >/etc/exports
    echo "/nfs/master   192.168.121.0/24(rw,sync,no_subtree_check)"   >>/etc/exports
    systemctl enable --now nfs-server || exit 1
    systemctl is-active nfs-server.service || exit 1
    firewall-cmd --permanent --add-service={nfs,mountd,rpc-bind} || exit 1
    exportfs -ar || exit 1
    
    firewall-cmd --permanent --add-port={179,6443,2379,2380,10250,10259,10257}/tcp
    if [[ ! -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] ; then
        DEFAULT_DEV=$(netstat -rn|grep "^0.0.0.0" |awk '{print $8}')
        if [[ -z ${DEFAULT_DEV} ]] ; then
            echo $0 error: DEFAULT_DEV not found, check command: netstat -rn >&2
            exit 1
        fi
        MY_IP=$(ifconfig ${DEFAULT_DEV} | grep "broadcast" | awk '{print $2}')

        echo EXEC: kubeadm init --pod-network-cidr ${POD_NETWORK_CIDR}  --apiserver-advertise-address=${MY_IP}
        kubeadm init --pod-network-cidr ${POD_NETWORK_CIDR}  --apiserver-advertise-address=${MY_IP} || exit 1  
        mkdir -p $K8S_HOME/.kube || exit 1
        cp -i /etc/kubernetes/admin.conf $K8S_HOME/.kube/config || exit 1
        chown -R k8s:k8s $K8S_HOME/.kube || exit 1
    else
        echo k8s is already initialized, when re-initialization is needed, destroy VMs via vagrant
    fi

    rm -f /tmp/join2cluster
    kubeadm token create --print-join-command >/tmp/join2cluster || exit 1  
    
    echo Installing helm - will be required later
    export PATH=$PATH:/usr/local/bin
    INSTALL_HELM_SH=/tmp/get_helm.sh
    curl -fsSL -o ${INSTALL_HELM_SH} https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 || exit 1
    chmod 700 ${INSTALL_HELM_SH} || exit 1
    ${INSTALL_HELM_SH} || exit 1
    rm -f ${INSTALL_HELM_SH}
    echo HELM is installed

    # itls tests needs full url - proxy node has ip 192.168.121.209 - will use is
    grep -q 192.168.121.209 /etc/hosts
    if [[ $? != "0" ]] ; then
        echo "# following ip is for itls, certificate must match !!!" >>/etc/hosts
        echo "192.168.121.209 itls-test.itls.com" >>/etc/hosts
    fi
else
    firewall-cmd --permanent --add-port={179,10250,30000-32767}/tcp    
fi
firewall-cmd --reload || exit 1
SCRIPT

############################################################################
# in previous steps we have prepared k8s join command, now command wil be copiet into worker VMs
copy_join_command_sh = <<-SCRIPT
test $(hostname -s) == "proxy-lb" && exit 0

if [[ ${HOSTNAME} = "master" ]] ; then
    K8S_HOME=$( getent passwd k8s | cut -d: -f6 )
    if [ -f /tmp/join2cluster ] ; then
        echo Copying join command to workers /tmp/join2cluster
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${K8S_HOME}/.ssh/k8s.key /tmp/join2cluster k8s@node1:/tmp
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${K8S_HOME}/.ssh/k8s.key /tmp/join2cluster k8s@node0:/tmp
    else
        echo $0 error: File /tmp/join2cluster not created
        exit 1
    fi
fi
SCRIPT

##########################################################################
# after join command was copiet into worker nodes, workers will join the cluster
joining_setup_sh = <<-SCRIPT
test $(hostname -s) == "proxy-lb" && exit 0

K8S_HOME=$( getent passwd k8s | cut -d: -f6 )

if [[ ${HOSTNAME} != "master" ]] ; then
    let I=0
    while :
    do
        if [ ! -f /tmp/join2cluster ] ; then
            if [ $I -gt 24 ] ; then
                echo $0 error: join command not delivered within 2 minutes >&2
                exit 1
            fi
            echo Waiting for file /tmp/join2cluster 
            sleep 5
            let I+=1
        else
            break
        fi
    done
    echo Joining cluster
    bash /tmp/join2cluster || exit 1
    rm -f /tmp/join2cluster 
fi
SCRIPT

######################################################################
# installing CNI (calico) on master node
install_cni_sh = <<-SCRIPT
test $(hostname -s) == "proxy-lb" && exit 0

if [[ $(hostname -s) == "master" ]] ; then
    export KUBECONFIG=/etc/kubernetes/admin.conf

    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml || exit 1        
    echo Waiting for cluster to become ready, waiting for 3 ready nodes, max 5 min
    let TTL=$(date +%s)+300
    while :
    do
        CNT=$(kubectl get nodes | grep ' Ready ' | wc -l)
        if [ $CNT -eq 3 ] ; then
            break
        fi
        if [ $(date +%s) -gt ${TTL} ] ; then
            echo $0 error: Cluster not ready in 5 minutes, check: kubectl get nodes
            exit 1
        fi
        sleep 17
        echo $(date)" Still waiting ... CNT=${CNT}"
    done
fi
exit 0
SCRIPT

######################################################################
# installing CNI (calico) on master node
open_firewall4cni_sh = <<-SCRIPT
test $(hostname -s) == "proxy-lb" && exit 0

echo Allowing calico network intercommunication, new zone, adding interfaces, firewall
ZONE_NAME=k8s_calico
firewall-cmd --get-zones | grep -q "${ZONE_NAME}"
if [[ $? != "0" ]] ; then
    firewall-cmd --permanent --new-zone=${ZONE_NAME} || exit 1
    firewall-cmd --permanent --zone=${ZONE_NAME} --set-target=ACCEPT || exit 1
    firewall-cmd --permanent --zone=${ZONE_NAME} --add-interface=cali+ || exit 1
    firewall-cmd --permanent --zone=${ZONE_NAME} --add-interface=tunl+ || exit 1
    firewall-cmd  --permanent --add-rich-rule='rule family="ipv4" protocol value="4" accept' || exit 1
    firewall-cmd --reload || exit 1
fi
SCRIPT

#################################################################
# # mount NFS on workers
mounting_nfs_on_clients_sh = <<-SCRIPT
test ${HOSTNAME} == "master" && exit 0
# nfs is accessed form nodes and proxy-lb

# # in workers we also mount NFS
df -k | grep -q master:/nfs
if [[ $? != "0" ]] ; then
    echo Mounting NFS from master node on bothe worker nodes
    mount master:/nfs/master /nfs/master
else
    echo NFS mounted
fi
exit 0
SCRIPT

#################################################################
# final tests
running_check_sh = <<-SCRIPT

if [[ $(hostname -s) == "proxy-lb" ]] ; then
    echo Verifying service status of squid
    while :
    do
        systemctl is-active squid.service | grep -q activating
        if [[ $? == "0" ]] ; then
            sleep 5
            continue
        fi
        break
    done
    systemctl is-active squid.service
    if [[ $? != "0" ]] ; then
        echo squid is not active, but: $(systemctl is-active squid.service)
        exit 1
    fi

    echo Verifying service status of nginx
    while :
    do
        systemctl is-active nginx.service | grep -q activating
        if [[ $? == "0" ]] ; then
            sleep 5
            continue
        fi
        break
    done
    systemctl is-active nginx.service 
    if [[ $? != "0" ]] ; then
        echo nginx is not active, but: $(systemctl is-active nginx.service)
        exit 1
    fi

    if [[ ! -f /home/k8s/nginx-mngr.sh ]] ; then
        echo $0 error: script /home/k8s/nginx-mngr.sh not found, unable to manager nginx LB >&2
        exit 1
    fi 
    exit 0
fi

# creating folder for files
rm -rf /tmp/k8s-files
mkdir /tmp/k8s-files || exit 1
chown k8s:k8s /tmp/k8s-files || exit 1
chmod 777  /tmp/k8s-files || exit 1

PROXY="-x http://proxy-lb:3128/"

RET=$(curl -s http://localhost:10248/healthz)
if [[ ${RET} != "ok" ]] ; then
    echo $0 error: problem on node $(hostname -s)
    exit 1
fi

if [[ $(hostname -s) == "master" ]] ; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    let TTL=$(date +%s)+300
    while :
    do
        CNT=$(kubectl get nodes | grep ' Ready ' | wc -l)
        if [ $CNT -eq 3 ] ; then
            break
        fi
        if [ $(date +%s) -gt ${TTL} ] ; then
            echo $0 error: Cluster not ready in 5 minutes, check: kubectl get nodes
            exit 1
        fi
        sleep 5
    done
    echo k8s cluster ready 
else  
    echo Check NFS mounts
    df -k | grep -q /nfs/master
    if [[ $? != "0" ]] ; then
        echo $0 error: NFS not ready, /nfs/master not mounted >&2
        showmount -e master >&2
        exit 1
    fi
    showmount -e master | grep -q /nfs/k8s
    if [[ $? != "0" ]] ; then
        echo $0 error: NFS not ready, /nfs/k8s not available >&2
        showmount -e master >&2
        exit 1
    fi
    echo Both NFS shares OK
fi

RV=$(curl -s ${PROXY}  -o /dev/null -w "%{http_code}" https://www.example.org/)
if [[ ${RV} != "200" ]] ; then
    echo $0 error: problem with internet connection: curl -s -x ${PROXY}  -o /dev/null -w "%{http_code}" https://www.example.org/
    exit 1
fi
echo Internet accessible 
nc -z www.sme.sk 443
if [[ $? == "0" ]] ; then
    echo $0 error: direct access to internet is still allowed, but it should not be 
    exit 1
fi
echo Using PROXY - direct internet access is not allowed

exit 0
SCRIPT

###############################################################
# blockin outgoing port 443/tcp to force PROXY usage
deny_outgoing_443_sh = <<-SCRIPT
test $(hostname -s) == "proxy-lb" && exit 0

# check for firewalld table in nft
# this is not clean solution - perhaps k8s change nft structure and this will stop work
nft -a list tables | grep -q firewalld
if [[ $? != "0" ]] ; then
    echo $0 error: nft table firewalld not found
    exit 1
fi

# looking for oifname "lo" accept # handle 287 which should be in chain filter_OUTPUT
HANDLE=$(nft -a list table inet firewalld |grep oifname | grep lo | awk '{print $6}')
if [[ -z ${HANDLE} ]] ; then
    echo $0 error: unable to find handle in chain filter_OUTPUT
    exit 1
fi   

nft insert rule inet firewalld filter_OUTPUT position ${HANDLE} tcp dport 443 log prefix \\"OUTGOING_443: \\" reject || exit 1
echo OUTPUT access to 443/tcp REJECTED, logged via syslog - but the rule is not saved !!!

exit 0
SCRIPT

#####################################################################
install_training_files_sh = <<-SCRIPT
test ${HOSTNAME} != "master" && exit 0

K8S_HOME=$( getent passwd k8s | cut -d: -f6 )
rm -rf ${K8S_HOME}/bin 
mkdir -p ${K8S_HOME}/bin || exit 1
cp -rp /tmp/k8s-files/* ${K8S_HOME}/bin || exit 1
cp -p /tmp/k8s-files/rasp-runtime-protection-ebpf.yaml /nfs/master || exit 1
rm -rf  /tmp/k8s-files/
chown -R k8s:k8s ${K8S_HOME}/bin || exit 1

# key and cert for itls test - domain name must match FQDN of 192.168.121.209
if [[ ! -f ${K8S_HOME}/itls.key ]] ; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/CN=itls-test.itls.com" \
        -keyout ${K8S_HOME}/itls.key  -out ${K8S_HOME}/itls.crt || exit 1
    chown -R k8s:k8s ${K8S_HOME}/itls.{key,crt} || exit 1
fi

SCRIPT

#####################################################################
exec_training_batch_sh = <<-SCRIPT
test $(hostname -s) != "master" && exit 0

K8S_HOME=$( getent passwd k8s | cut -d: -f6 )
if [[ -f ${K8S_HOME}/bin/run_training.sh ]] ; then
    sudo -E -u k8s bash ${K8S_HOME}/bin/run_training.sh
    exit $?
else
    echo $0 error: script ${K8S_HOME}/bin/run_training.sh not found
    exit 1
fi
SCRIPT
#####################################################################
Vagrant.configure("2") do |config|
  
  #config.vm.box          = "rockylinux/9"
  config.vm.box           = "generic/rocky9"
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # config.vm.provider "libvirt" do |v|
  #     v.memory = 4096
  #     v.cpus = 4
  #     v.graphics_type = 'none'
  # end

  config.vm.define "master" do |master|
    master.vm.hostname    = "master"
    master.vm.provider "libvirt" do |v|
      v.memory        = mem_for_k8s_master
      v.cpus          = cpu_for_k8s_master
      v.graphics_type = 'none'
      v.uri           = "qemu:///system"
    end
    master.vm.network :private_network, ip: "10.10.10.10"
  end

  config.vm.define "node0" do |node0|
    node0.vm.hostname    = "node0"
    node0.vm.provider "libvirt" do |v|
      v.memory        = mem_for_k8s_worker
      v.cpus          = cpu_for_k8s_worker
      v.graphics_type = 'none'
      v.uri           = "qemu:///system"  
    end
    node0.vm.network :private_network, :ip => '10.10.10.20'
  end

  config.vm.define "node1" do |node1|
    node1.vm.hostname    = "node1"
    node1.vm.provider "libvirt" do |v|
      v.memory        = mem_for_k8s_worker
      v.cpus          = cpu_for_k8s_worker
      v.graphics_type = 'none'
      v.uri           = "qemu:///system"  
    end
    node1.vm.network :private_network, :ip => '10.10.10.21'
  end

  config.vm.define "proxy-lb" do |proxy|
    proxy.vm.hostname    = "proxy-lb"
    proxy.vm.provider "libvirt" do |v|
      v.memory        = mem_for_support_vm
      v.cpus          = cpu_for_support_vm
      v.graphics_type = 'none'
      v.uri           = "qemu:///system"  
    end
    proxy.vm.network :private_network, :ip => '10.10.10.99'
  end

  config.vm.provision "system-init",          type: "shell",    run: "once", path: "./rocky9_baseline_setup.sh", \
    env: {"DO_INCLUDE_FALCO" => ENV['DO_INCLUDE_FALCO']}
  config.vm.provision "reload-after-update",  type: "reload",   run: "once"
  config.vm.provision "copy-k8s-priv-key",    type: "file",     run: "once", source: "./k8s.key",     destination: "/tmp/k8s.key"
  config.vm.provision "copy-k8s-pub-key",     type: "file",     run: "once", source: "./k8s.key.pub", destination: "/tmp/k8s.key.pub"
  config.vm.provision "prepare-k8s-account",  type: "shell",    run: "once", path: "./prepare-k8s-account.sh"
  config.vm.provision "firewall-n-proxy",     type: "shell",    run: "once", path: "./firewall_n_proxy_setup.sh", \
    env: {"DO_USE_PROXY" => ENV['DO_USE_PROXY']}

  #config.vm.provision "app-init",             type: "shell",    run: "once", path:  "./k8s-install-n-intit.sh", \
  #  env: {"POD_NETWORK_CIDR" => ENV['POD_NETWORK_CIDR']}
  # config.vm.provision "copy_join_command", type: "shell", run: "once", :inline => copy_join_command_sh
  # config.vm.provision "join-cluster", type: "shell", run: "once", :inline => joining_setup_sh, \
  #     env: {"POD_NETWORK_CIDR" => ENV['POD_NETWORK_CIDR']}
  # config.vm.provision "install_cni", type: "shell", run: "once", :inline => install_cni_sh
  # config.vm.provision "open_firewall4cni",    type: "shell", run: "once", :inline => open_firewall4cni_sh
  # config.vm.provision "running_check",        type: "shell", run: "once", :inline => running_check_sh
  # config.vm.provision "mount_nfs_on_clients", type: "shell", run: "once", :inline => mounting_nfs_on_clients_sh
  # config.vm.provision "deny_tcp443",          type: "shell", run: "once", :inline => deny_outgoing_443_sh
  # config.vm.provision "proxy_setup", type: "shell", run: "once", :inline => proxy_setup_sh
  # config.vm.provision "copy-nginx-config", type: "file", source: "./nginx-lb-ingress.conf", destination: "/tmp/nginx-lb-ingress.conf", run: "once"
  # config.vm.provision "copy-nginx-mngr", type: "file", source: "./nginx-mngr.sh", destination: "/tmp/nginx-mngr.sh", run: "once"
  # config.vm.provision "copy-k8s-files", type: "file", source: "./k8s-files/", destination: "/tmp/k8s-files", run: "once"
  # config.vm.provision "install_training_files", type: "shell", run: "once", :inline => install_training_files_sh 
  # config.vm.provision "exec_training_batch", type: "shell", run: "once", :inline => exec_training_batch_sh
end