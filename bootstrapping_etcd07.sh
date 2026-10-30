#!/bin/bash
#This script is for checking and bootstrapping the server(etcd) machine for the first time with appropriate components and files and permissions configured on the etcd daemon...
set -euo pipefail
set -x
if [ $EUID -ne 0 ]; then
    echo "must run as root!" >&2
    exec sudo bash "$0" "$@"
fi

echo "copying etcd binaries and systemd unig files to server machine"
host=controlplane
cd /home/jumpbox/kubernetes-the-hard-way

scp ./downloads/controller/etcd \
    ./downloads/client/etcdctl \
    ./units/etcd.service \
    root@"${host}":~/

cert_dir_path=/home/jumpbox/kubernetes-the-hard-way/certs
files=(
	ca.crt
	kube-apiserver.crt
	kube-apiserver.key
	)

#Bootstrap the machine over ssh
#cp the certs first
copy_certs (){
for file in "${files[@]}"; do
		scp "${cert_dir_path}/${file}" root@"${host}":~/
	done

	ssh -n root@"${host}" 'bash -s' <<'REMOTE_EOF'
	set -euo pipefail
	set -x
	mkdir -vp /etc/etcd /var/lib/etcd/
	chmod 700 /etc/etcd /var/lib/etcd/
	mv -v ~/etc ~/etcdctl /usr/local/bin/
	mv -v ~/etcd.service /etc/systemd/system/
	systemctl daemon-reload
	systemctl enable --now etcd
	systemctl start etcd
	systemctl is-active etcd
	systemctl status etcd.service --no-pager
	etcdctl member list
REMOTE_EOF

	}
main (){
	copy_certs 
}
echo "etcd Bootstrap complete on ${host}"

main "$@"
