#!/bin/bash
#this script is to configure kubectl over jumpbox machine
set -euo pipefail
if [ $EUID -ne 0 ]; then
    echo "Running as root"
    exec sudo bash "$0" "$@"
fi

curl --cacert ca.crt https://controlplane.kubernetes.local:6443/version

generate_kubeconfig (){
    kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --emebed-certs=true \
    --server=https://controlplane.kubernetes.local:6443

    kubectl set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \

    kubectl config set-context kubernetes-the-hard-way \
    --cluster=kubernetes-the-hard-way \
    --user=admin

    kubectl config use-context kubernetes-the-hard-way 
}
#check the kubectl version
kubectl version
kubectl get nodes

#if the output shows the worker vms that is nodes are online and status=ready then the cluster is online.

main (){
    generate_kubeconfig 
}

main "$@"