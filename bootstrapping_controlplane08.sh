#!/bin/bash
# This file is to combine all controlplane components and start the server

set -euo pipefail
set -x

if [ $EUID -ne 0 ]; then
    echo "must run as root!" >&2
    exec sudo bash "$0" "$@"
fi

# copy the relevant files from jump box to server machine
WORK_DIR=/home/jumpbox/kubernetes-the-hard-way
cd "${WORK_DIR}"

host=controlplane

scp \
    "${WORK_DIR}/downloads/controller/kube-apiserver" \
    "${WORK_DIR}/downloads/controller/kube-controller-manager" \
    "${WORK_DIR}/downloads/controller/kube-scheduler" \
    "${WORK_DIR}/downloads/client/kubectl" \
    "${WORK_DIR}/units/kube-apiserver.service" \
    "${WORK_DIR}/units/kube-controller-manager.service" \
    "${WORK_DIR}/units/kube-scheduler.service" \
    "${WORK_DIR}/configs/kube-scheduler.yaml" \
    "${WORK_DIR}/configs/kube-apiserver-to-kubelet.yaml" \
    root@"${host}":~/

# now make the relevant directories in the server machine
ssh -n root@"${host}" 'bash -s' <<REMOTE_SSH
set -euo pipefail
set -x

# first make the directories
mkdir -vp /etc/kubernetes/config
mkdir -vp /var/lib/kubernetes

# move the binaries to /usr/local/bin/
mv -v ~/kube-apiserver ~/kube-controller-manager ~/kube-scheduler ~/kubectl /usr/local/bin/

# move the certs to /var/lib/kubernetes/
mv -v ~/kube-apiserver.key ~/kube-apiserver.crt ~/service-accounts.key ~/service-accounts.crt ~/ca.key ~/ca.crt ~/encryption-config.yaml /var/lib/kubernetes/

# move yaml files to /etc/kubernetes/config/
mv -v ~/kube-scheduler.yaml /etc/kubernetes/config/
mv -v ~/kube-apiserver-to-kubelet.yaml /etc/kubernetes/config/

# move the kubeconfig files to /var/lib/kubernetes/
mv -v ~/kube-controller-manager.kubeconfig /var/lib/kubernetes/
mv -v ~/kube-scheduler.kubeconfig /var/lib/kubernetes/
mv -v ~/admin.kubeconfig /var/lib/kubernetes/

# move the unit files to /etc/systemd/system/
mv -v ~/kube-apiserver.service /etc/systemd/system/
mv -v ~/kube-controller-manager.service /etc/systemd/system/
mv -v ~/kube-scheduler.service /etc/systemd/system/

# start the services
systemctl daemon-reload
for svc in kube-apiserver kube-controller-manager kube-scheduler; do
    systemctl enable "\$svc".service
    systemctl start "\$svc".service
    systemctl is-active "\$svc".service
done

# verify the services
systemctl status kube-apiserver.service --no-pager
journalctl -xeu kube-apiserver.service -n 50 --no-pager

# finally check kubectl client
echo "verifying the kubectl client [*]....."
kubectl cluster-info --kubeconfig /var/lib/kubernetes/admin.kubeconfig
kubectl apply -f /etc/kubernetes/config/kube-apiserver-to-kubelet.yaml --kubeconfig /var/lib/kubernetes/admin.kubeconfig

# check whether curl is installed or not
echo "checking curl status"
package=curl
status=0
if dpkg -l "\$package" > /dev/null 2>&1 ; then
    ((++status))
    echo "\$package installed"
else
    echo "\$package not installed...status: \$status"
    echo "Installing package...."
    apt install "\$package" -y
fi

curl --cacert /var/lib/kubernetes/ca.crt https://controlplane.kubernetes.local:6443/version
REMOTE_SSH

echo "Bootstrapping complete on ${host}."

