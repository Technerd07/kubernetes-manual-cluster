#!/bin/bash
set -euo pipefail 
set -x

if [ $EUID -ne 0 ]; then
    echo "running as root user!!"
    exec sudo bash "$0" "$@"
fi

NODES=(node-0 node-1)
COMPONENTS=(admin kube-apiserver kube-scheduler kube-controller-manager)
SERVER=https://controlplane.kubernetes.local:6443
CERTS_PATH=/home/jumpbox/kubernetes-the-hard-way/certs
CLUSTER=kubernetes-the-hard-way

#check status of the machines
check_status (){
    for node in "${NODES[@]}"; do
        if ping -c 3 -W 2 "${node}" &>/dev/null; then
            echo "${node}" reachable
	    check_directory "${node}"
        else 
            echo "${node} failed! un-reachable skipping...." >&2 
	    continue
        fi
    done
}
check_directory (){
	local node=$1
    dir=/var/lib/kubelet
        ssh -n root@"${node}" "mkdir -vp '${dir}' 2>/dev/null" \
        && echo "${dir} ready on node ${node}"
}
generate_kube_config (){
local host=$1 user=$2
    kubectl config set-cluster "${CLUSTER}" \
    --certificate-authority="$CERTS_PATH/ca.crt" \
    --embed-certs=true \
    --server="${SERVER}" \
    --kubeconfig="$CERTS_PATH/${host}.kubeconfig"
    
    kubectl config set-credentials "${user}" \
    --client-certificate="$CERTS_PATH/${host}.crt" \
    --client-key="$CERTS_PATH/${host}.key" \
    --embed-certs=true \
    --kubeconfig="$CERTS_PATH/${host}.kubeconfig"

    kubectl config set-context default \
    --cluster="${CLUSTER}" \
    --user="${user}" \
    --kubeconfig="$CERTS_PATH/${host}.kubeconfig"

    kubectl config use-context default \
    --kubeconfig="$CERTS_PATH/${host}.kubeconfig"

}
copy_kubeconfig (){
    local hosts=$1
    #here im planning to include $CERTS_PATH before $Host maybe it could work... 
    scp "$CERTS_PATH/${node}.kubeconfig" root@"${host}":~/
}
main (){
    #first check status
    check_status 
    echo "Generating Kubeconfig files for Nodes and copying [*]....."
    for host in "${NODES[@]}"; do
	    if ping -c 5 -W 2 "${host}" &>/dev/null; then 
        	generate_kube_config "${host}" "system:node:${host}"
        	copy_kubeconfig "${host}"
	    else
		echo "skipping kubeconfig for ${host} (offline)"
	    fi
    done
    echo "Generating Kubeconfig files for Controplane vm [*]....."
    for comp in "${COMPONENTS[@]}"; do 
        generate_kube_config "${comp}" "system:${comp}"
    done
    generate_kube_config "admin" "admin"
    scp "${CERTS_PATH}/admin.kubeconfig" root@"controlplane":~/
    echo "Configuration completed successfully...."
}
main "$@"
