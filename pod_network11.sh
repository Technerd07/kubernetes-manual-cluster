#!/bin/bash
#Run this from the jumpbox machine
set -euo pipefail
if [ $EUID -ne 0 ]; then
    echo "Running as root"
    exec sudo bash "$0" "$@"
fi
hosts=(controlplane node-0 node-1)
cd /home/jumpbox/kubernetes-the-hard-way/
SERVER_IP=$(grep server machines.txt | cut -d " " -f 1)
NODE_0_IP=$(grep node-0 machines.txt | cut -d " " -f 1)
NODE_0_SUBNET=$(grep node-0 machines.txt | cut -d " " -f 5)
NODE_1_IP=$(grep node-1 machines.txt | cut -d " " -f 1)
NODE_1_SUBNET=$(grep node-1 machines.txt | cut -d " " -f 5)

ssh root@controlplane <<REMOTE_SERVER
    ip route replace "${NODE_0_SUBNET}" via "${NODE_0_IP}"
    ip route replace "${NODE_1_SUBNET}" via "${NODE_1_IP}"
REMOTE_SERVER

#ssh root@node-0 <<REMOTE_NODE-0
#ip route replace "${NODE_1_SUBNET}" via "${NODE_1_IP}"
#REMOTE_NODE-0

ssh root@node-1 <<REMOTE_NODE-1
ip route replace "${NODE_0_SUBNET}" via "${NODE_0_IP}"
REMOTE_NODE-1

for host in "${hosts[@]}"; do 
    ssh root@"${host}"
done


