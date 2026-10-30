#!/bin/bash
#This section of the script must be run on the jumpbox machine over ssh

set -euo pipefail

if [ $EUID -ne 0 ]; then
    echo "Running as root."
    exec sudo bash "$0" "$@"
fi

cd /home/jumpbox/kubernetes-the-hard-way/
hosts=(node-0 node-1)
#set the subnet to the nodes over ssh
for host in "${hosts[@]}"; do
    SUBNET=$(grep ${HOST} machines.txt | cut -d " " -f 5)
  sed "s|SUBNET|$SUBNET|g" \
    configs/10-bridge.conf > 10-bridge.conf
  sed "s|SUBNET|$SUBNET|g" \
    configs/kublet-config.yaml > kubelet-config.yaml
done

ls -al {kubelet-config.yaml,10-bridge.conf} 

#now copy the files to respective nodes
for host in "${hosts[@]}"; do
    scp ./kubelet-config.yaml 10-bridge.conf root@"${host}":~/
done
echo "worker node configs deployed"
