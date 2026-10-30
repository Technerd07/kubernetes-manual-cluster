#!/usr/bin/env bash
# configuration-05.sh - build, verify and install the kubeconfig files
# Usage: configuration-05.sh [--no-copy] [--restart] [-h]
set -Eeuo pipefail
if [[ ${DEBUG:-0} == 1 ]]; then set -x; fi

if [[ $EUID -ne 0 ]]; then
  echo 'Not root, re-running with sudo...' >&2
  exec sudo -- "$BASH" "$0" "$@"
fi

REPO_PATH=${REPO_PATH:-/home/jumpbox/kubernetes-the-hard-way}
CERT_DIR=${CERT_DIR:-$REPO_PATH/certs}
NODES=(node-0 node-1)
CONTROLPLANE=controlplane
CLUSTER=kubernetes-the-hard-way
SERVER_PUBLIC=https://controlplane.kubernetes.local:6443   # used by kubelet, kube-proxy, jumpbox kubectl
SERVER_LOCAL=https://127.0.0.1:6443                        # used on the controlplane itself
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
COPY=1 RESTART=0

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

log()  { printf '%s [%s] %s\n' "$(date +%T)" "$1" "${*:2}" >&2; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
die()  { log ERROR "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [options]
  --no-copy   build and verify only
  --restart   restart the services after copying
  -h, --help  show this help
EOF
}

require() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing dependency: $c"; done
}

reachable() { ssh "${SSH_OPTS[@]}" "root@$1" true 2>/dev/null; }

cn_of() {
  openssl x509 -in "$1" -noout -subject -nameopt RFC2253 |
    awk -F'CN=' '{split($2, a, ","); print a[1]}'
}

# decode the cert/key embedded in a kubeconfig and compare them with the source files
verify_kubeconfig() {   # usage: verify_kubeconfig <kubeconfig> <cert-name>
  local f=$1 cert=$2
  kubectl config view --kubeconfig="$f" --raw \
    -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d >"$TMP/c"
  kubectl config view --kubeconfig="$f" --raw \
    -o jsonpath='{.users[0].user.client-key-data}' | base64 -d >"$TMP/k"
  [[ -s $TMP/c ]] || die "${f##*/} has no client-certificate-data"
  [[ -s $TMP/k ]] || die "${f##*/} has no client-key-data"
  cmp -s "$TMP/c" "$CERT_DIR/$cert.crt" || die "${f##*/} embeds a different certificate than $cert.crt"
  cmp -s "$TMP/k" "$CERT_DIR/$cert.key" || die "${f##*/} embeds a different key than $cert.key"
  openssl verify -CAfile "$CERT_DIR/ca.crt" "$TMP/c" >/dev/null 2>&1 ||
    die "${f##*/}: embedded certificate is not signed by ca.crt"
  info "ok: ${f##*/} -> $(cn_of "$TMP/c")"
}

make_kubeconfig() {   # usage: make_kubeconfig <output-name> <cert-name> <server-url>
  local name=$1 cert=$2 server=$3 out="$CERT_DIR/$1.kubeconfig" user
  [[ -s $CERT_DIR/$cert.crt && -s $CERT_DIR/$cert.key ]] ||
    die "missing $cert.crt or $cert.key (run certscript.sh first)"
  user=$(cn_of "$CERT_DIR/$cert.crt")        # the user name is the certificate CN
  rm -f -- "$out"                            # never append to an old file

  kubectl config set-cluster "$CLUSTER" \
    --certificate-authority="$CERT_DIR/ca.crt" --embed-certs=true \
    --server="$server" --kubeconfig="$out" >/dev/null
  kubectl config set-credentials "$user" \
    --client-certificate="$CERT_DIR/$cert.crt" \
    --client-key="$CERT_DIR/$cert.key" --embed-certs=true \
    --kubeconfig="$out" >/dev/null
  kubectl config set-context default \
    --cluster="$CLUSTER" --user="$user" --kubeconfig="$out" >/dev/null
  kubectl config use-context default --kubeconfig="$out" >/dev/null
  chmod 600 "$out"
  verify_kubeconfig "$out" "$cert"
}

build_all() {
  local h
  for h in "${NODES[@]}"; do make_kubeconfig "$h" "$h" "$SERVER_PUBLIC"; done
  make_kubeconfig kube-proxy              kube-proxy              "$SERVER_PUBLIC"
  make_kubeconfig kube-controller-manager kube-controller-manager "$SERVER_LOCAL"
  make_kubeconfig kube-scheduler          kube-scheduler          "$SERVER_LOCAL"
  make_kubeconfig admin                   admin                   "$SERVER_LOCAL"
  make_kubeconfig admin-remote            admin                   "$SERVER_PUBLIC"   # for kubectl on the jumpbox
}

distribute() {
  local h
  for h in "${NODES[@]}"; do
    if ! reachable "$h"; then warn "$h unreachable over ssh, skipping"; continue; fi
    ssh "${SSH_OPTS[@]}" "root@$h" 'mkdir -p /var/lib/kubelet /var/lib/kube-proxy'
    scp -q "${SSH_OPTS[@]}" "$CERT_DIR/$h.kubeconfig" "root@$h:/var/lib/kubelet/kubeconfig"
    scp -q "${SSH_OPTS[@]}" "$CERT_DIR/kube-proxy.kubeconfig" "root@$h:/var/lib/kube-proxy/kubeconfig"
    ssh "${SSH_OPTS[@]}" "root@$h" 'chmod 600 /var/lib/kubelet/kubeconfig /var/lib/kube-proxy/kubeconfig'
    info "installed kubeconfigs on $h"
  done

  if ! reachable "$CONTROLPLANE"; then warn "$CONTROLPLANE unreachable, skipping"; return 0; fi
  ssh "${SSH_OPTS[@]}" "root@$CONTROLPLANE" 'mkdir -p /var/lib/kubernetes'
  scp -q "${SSH_OPTS[@]}" \
    "$CERT_DIR/kube-controller-manager.kubeconfig" "$CERT_DIR/kube-scheduler.kubeconfig" \
    "root@$CONTROLPLANE:/var/lib/kubernetes/"
  scp -q "${SSH_OPTS[@]}" "$CERT_DIR/admin.kubeconfig" "root@$CONTROLPLANE:~/admin.kubeconfig"
  ssh "${SSH_OPTS[@]}" "root@$CONTROLPLANE" \
    'chmod 600 /var/lib/kubernetes/*.kubeconfig ~/admin.kubeconfig'
  info "installed kubeconfigs on $CONTROLPLANE"
}

restart_services() {
  local h
  info "restarting control plane services (order matters)"
  ssh "${SSH_OPTS[@]}" "root@$CONTROLPLANE" \
    'systemctl restart etcd kube-apiserver kube-controller-manager kube-scheduler' ||
    warn "control plane restart reported a problem"
  sleep 5
  for h in "${NODES[@]}"; do
    ssh "${SSH_OPTS[@]}" "root@$h" 'systemctl restart kubelet kube-proxy' ||
      warn "restart on $h reported a problem"
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)  usage; exit 0 ;;
      --no-copy)  COPY=0 ;;
      --restart)  RESTART=1 ;;
      *)          die "unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require kubectl openssl ssh scp awk cmp base64
  [[ -s $CERT_DIR/ca.crt ]] || die "missing $CERT_DIR/ca.crt"
  build_all
  if (( COPY )); then distribute; fi
  if (( COPY && RESTART )); then restart_services; fi
  info 'kubeconfigs done'
}

main "$@"
