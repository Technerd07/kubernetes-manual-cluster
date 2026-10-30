#!/bin/bash
#configure the ssh server in all vms
#This script is run on the jumpbox machine to configure the ssh server and generate ssh keys for passwordless authentication to other vms
set -euo pipefail

FQDN=("controlplane.kubernetes.local","node-0.kubernetes.local","node-1.kuberenetes.local");
IP=(192.168.56.10 192.168.56.11 192.168.56.12 192.168.56.13)
HOSTS=("controlplane","node-0","node-1")


if [ "$EUID" -ne 0 ];then
	echo "Running as root User....."
	exec sudo bash "$0" "$@"
fi

echo "Configuring the SSH Server [*]....."
status=$(systemctl is-active ssh)

if [ -f /etc/ssh/sshd_config ]; then
	echo "SSH server is already installed and configured."
else
	echo "Installing ssh server and configuring it...."
	apt install openssh-server -y
fi
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

echo "Restarting ssh service [*]....."
systemctl restart sshd.service

echo "Generating and disrtibuting the ssh keys [*]....."

ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""

ls -al /root/.ssh/*

echo "checking online status of hosts [*]....."

for host in "${FQDN[@]}";do
	if ping -c 5 "$host" &> /dev/null; then
		status=$? 
		if [ $status -eq 0 ]; then 
			echo "$host is online."
		else 
			echo "$host is offline exit status $status"
		fi
	fi
done

echo "copying the public key to remote hosts [*]....."
for ip in "${IP[@]}"; do
	ssh-copy-id root@${ip}
done
