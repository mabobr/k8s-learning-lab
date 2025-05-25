# k8s-learning-lab
Yet another learning project to build k8s clister in vagrant

## What
Vagrantfile and some shells to create 1 master + 2 worker nodes k8s + 1 supporting server 

```
git clone git@github.com:mabobr/k8s-learning-lab.git
cd k8s-learning-lab
# Createing ssh keys for internal cluster communication
ssh-keygen -t ed25519 -f ./k8s.key -q -N ""
# Consult and set variables in Vagrantfile
vagrant up
```