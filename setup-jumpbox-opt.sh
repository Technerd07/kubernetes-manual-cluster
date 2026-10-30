#!/bin/bash



set -euo pipefail
 if [ $EUID -ne 0 ]; then
    echo "Running as root "
    exec sudo bash "$0" "$@"
 fi
path_to_home=/home/jumpbox/
repo_name=kubernetes-the-hard-way
repo_path=/home/jumpbox/kubernetes-the-hard-way/
 
echo "Updating system binaries [*]....."


apt-get update && apt-get upgrade -y

echo "Installing Required Packages [*]....."
packages=(curl git openssl vim wget)

#install the packages

for package in "${packages[@]}";  do 
    apt install "${package}" -y
done 
#first change the dir to /home/jumpbox
cd "${path_to_home}"

#check if the repo exists on the system

if [ -d "${path_to_home}/${repo_name}" ]; then
    echo "Directory present in the location"
else
    git clone --depth 1 https://github.com/kelseyhightower/kubernetes-the-hard-way.git
fi


#change the pwd to kubernetes-the-hard-way
cd "${path_to_home}/${repo_name}"
#before that check if the git repo is present in the filesystem 
if [ -d "${path_to_home}/${repo_name}/.git" ]; then  
    echo "Repo already exists at ${repo_name}, updating...."
    cd "${repo_path}" 
    git fetch --all 
fi

echo "Check the system architecture"
echo "System ARCH: " dpkg --print-architecture


cat downloads-$(dpkg --print-architecture).txt
echo "Downloading the required binaries [*]....."

wget -q --show-progress --https-only --timestamping  \
-P downloads -i downloads-$(dpkg --print-architecture).txt

echo "Extacting the binaries [*]....."
ARCH=$(dpkg --print-architecture)
mkdir -pv downloads/{client,cni-plugins,controller,worker}
tar -xvf downloads/crictl-v1.32.0-linux-${ARCH}.tar.gz -C downloads/worker
tar -xvf downloads/containerd-2.1.0-beta.0-linux-${ARCH}.tar.gz \
--strip-components 1 -C downloads/worker
tar -xvf downloads/cni-plugins-linux-${ARCH}-v1.6.2.tgz -C downloads/cni-plugins
tar -xvf downloads/etcd-v3.6.0-rc.3-linux-${ARCH}.tar.gz  \
--strip-components 1 \
-C downloads/ \
etcd-v3.6.0-rc.3-linux-${ARCH}/etcdctl \
etcd-v3.6.0-rc.3-linux-${ARCH}/etcd 
mv -v downloads/{etcdctl,kubectl} downloads/client/
mv -v downloads/{etcd,kube-apiserver,kube-scheduler,kube-controller-manager} \
downloads/controller/
mv -v downloads/{kubelet,kube-proxy} downloads/worker/
echo "Creating runc directory [*]....."
mkdir -pv downloads/worker/runc/
mv -v downloads/runc.$(dpkg --print-architecture) downloads/worker/runc

echo "removing the downloaded tar files [*]....."
rm -fr downloads/*.tar.gz
echo "making te binaries executable with proper file permissions[*]....."
chmod +x downloads/{client,cni-plugins,controller,worker}/*

echo "Check installed binaries [*]....."
ls -hl downloads/{client,cni-plugins,controller,worker}/

echo "Installing Kubectl [*]....."
cp -v downloads/client/kubectl /usr/local/bin/

echo "Check the binary file inside /usr/local/bin/ [*]....."
find /usr/local/bin/ -type f -executable -exec ls -lh {} \; | grep kubectl
echo "check the kubectl version [*]....."
kubectl version --client

echo "Jumpbox setup completed successfully [*]....."




