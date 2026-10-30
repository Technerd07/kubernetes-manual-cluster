#!/bin/bash
#This script file is used to assign the hostnames for the controlplane and nodes on the cluster

#First crate a file that holds the hostnames fqdn and ip of machines
#run this script from the jumpbox client machine
set -euo pipefail
set -x
if [ -$EUID -ne 0 ]; then
	echo "running as root"
	exec sudo "$0" "$@"

fi

cd /home/jumpbox/kubernetes-the-hard-way

entries=(
"192.168.56.10 jumpbox.kubernetes.local jumpbox"
"192.168.56.11 controlplane.kubernetes.local controlplane"
"192.168.56.12 node-0.kubernetes.local node-0 10.200.0.0/24"
"192.168.56.13 node-1.kubernetes.local node-1 10.200.1.0/24"
)
echo "check status: $?"

echo "appending hostnames to /etc/hosts file [*]....."
#check if the hostnames are already written if the project has previously been implemented..
for entry in "${entries[@]}"; do 

	if grep -qF "${entry}" /etc/hosts; then
		echo "Adding:" "${entry}"
	else
		echo "${entry}" >> /etc/hosts

	fi
done

#check wether the host is online and then register the entries into /etc/hosts
hostname_entry (){
	for entry in "${entries[@]}"; do 
		read -r IP FQDN HOSTNAME SUBNET <<<"${entry}"
		if ping -c 5 -W 2 "${HOSTNAME}" >&/dev/null; then
			echo "Host Online..."
			CMD="sed -i 's/^127.0.1.1.*/127.0.1.1\t${FQDN} ${HOSTNAME}/' /etc/hosts"
			ssh -n root@${IP} "$CMD"
			ssh -n root@${IP} hostnamectl set-hostname ${HOSTNAME}
			ssh -n root@${IP} systemctl restart systemd-hostnamed
			ssh -n root@${IP} hostname
		else
			echo "Host offline"
			continue
		fi
	done	
} 

main (){
	hostname_entry
}
main "$@"
