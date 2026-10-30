#!/bin/bash
#This script file is to generate data enc keys and store them in contolplane server machine which runs etcd database for the cluster

set -euo pipefail
set -x
if [ $EUID -ne 0 ]; then
    echo "non root user!"
    exec sudo bash "$0" "$@"
fi

WORK_DIR=/home/jumpbox/kubernetes-the-hard-way
echo "current working directory: '$(pwd)' "
echo "generating encryption-config.yaml file [*]....."
export ENCRYPTION_KEY="$(head -c 32 /dev/urandom | base64)"
#export variable is stored on the shell , when the command envsubst gets called it sees th etemplate file to replace taking the reference of the export variable and then replaces its value on the yaml file accordingly
envsubst < "${WORK_DIR}"/configs/encryption-config.yaml > "${WORK_DIR}"/encryption-config.yaml
chmod 600 "${WORK_DIR}"/encryption-config.yaml

sleep 3
echo "copying the config file to controller instance "
#host=controlplane.kubernetes.local
host=controlplane
scp "${WORK_DIR}"/encryption-config.yaml root@"${host}":~/


#main "$@"
