#!/bin/bash
set -euo pipefail

CERTS_DIR="/home/jumpbox/kubernetes-the-hard-way/certs"

cd "${CERTS_DIR}"

# Generate private key
openssl genrsa -out kube-apiserver.key 2048

# Generate CSR using the [kube-apiserver] section in ca.conf
openssl req -new -key kube-apiserver.key -sha256 \
  -config ca.conf -section kube-apiserver \
  -out kube-apiserver.csr

# Sign the CSR with the cluster CA
openssl x509 -req -days 3653 -in kube-apiserver.csr \
  -copy_extensions copyall \
  -sha256 -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out kube-apiserver.crt

chmod 600 kube-apiserver.key
echo "✅ Generated kube-apiserver.key, kube-apiserver.csr, and kube-apiserver.crt in ${CERTS_DIR}"

