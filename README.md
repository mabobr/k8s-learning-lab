# ToDO:
## Problem w/ reloadin nftables - still do not have correct way

# How:
# run script ./start-or-build-cluster.sh

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

## Next - PersVol on NFS
- NFS is prepared for shared volume (DONE)
- pv manifest is being copied on master (DONE)
- folder for file, to be sopied to master ready (DONE)
  - inside: deployer.sh as script to deploy <-- check variables inside (DONE)
  - 1sg manifest for persvolume (DONE)
- NEXT: from Vagrantfile and starts... script launcg deployer, with variables set
- deploy busybox as web server
