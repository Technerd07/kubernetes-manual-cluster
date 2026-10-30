#!/bin/bash

set -euo pipefail
set -x
if [ "$EUID" -ne 0 ]; then
	echo "running as root"
	exec sudo "$0" "$@"
fi

repo_path=/home/jumpbox/kubernetes-the-hard-way
cert_dir_path="$repo_path/certs"

if [ -d "$cert_dir_path" ]; then
	echo "dir found"
else
	mkdir -vp "$cert_dir_path"
fi

openssl genrsa -out "$cert_dir_path/ca.key" 4096 
openssl req -x509 -new -sha512 -noenc \
-key "$cert_dir_path/ca.key" -days 3653 \
--config "$cert_dir_path/ca.conf" \
-out "$cert_dir_path/ca.crt" 


#check if the dir contains all req certs

	certs=(
			"admin"
		 	"kube-apiserver"
			"kube-controller-manager"
			"kube-scheduler"
			"service-accounts"
			"kube-proxy"
			"kubelet"
			"admin"
			"node-0"
			"node-1"
	
		)

generate_certs (){
	allfound=true
for cert in "${certs[@]}"; do
	for ext in crt key csr; do
		if [[ ! -f  "$cert_dir_path/${cert}.${ext}" ]]; then
			allfound=false;
			break;
		fi
	done
done

if $allfound; then
	echo "All certificates already generated,Certificate Generation skipping...."
	sleep 2
else
			for component in "${certs[@]}"; do 
			openssl genrsa -out "$cert_dir_path/${component}.key" 4096
			openssl req -new -key "$cert_dir_path/${component}.key" -sha256 \
				-config "$cert_dir_path/ca.conf" \
				-out "$cert_dir_path/${component}.csr"

			openssl x509 -req -days 3653 -in "$cert_dir_path/${component}.csr" \
				-copy_extensions copyall \
				-sha256 -CA "$cert_dir_path/ca.crt" \
				-CAkey "$cert_dir_path/ca.key" \
				-CAcreateserial \
				-out "$cert_dir_path/${component}.crt"
			done
		fi
}

#check the directory with all specific certs and keys files
ls -al "$cert_dir_path" | grep -E '\.crt|\.key|\.csr' 

hosts=(node-0 node-1)
make_dirand_copyFiles(){
	for host in "${hosts[@]}"; do
		if ping -c 5 "${host}" &>/dev/null; then
			echo "Host Online"
		#first create direcotires and copy the certs and keys to node machines
		dir="/var/lib/kubelet"
		mkdir -vp "${dir}"
		scp "$cert_dir_path"/"${host}".{key,crt} root@"${host}":/var/lib/kubelet/
		else
			echo "Host ${host} offline "
			continue
			return 1
		fi
	done
	return 0
}


main (){
	generate_certs
	make_dirand_copyFiles
}


main "$@"

