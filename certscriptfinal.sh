#!/usr/bin/env bash
# certscript.sh - create / verify the cluster PKI and install it on the machines
# Usage: certscript.sh [--force] [--new-ca] [--no-copy] [-h]
set -Eeuo pipefail
if [[ ${DEBUG:-0} == 1 ]]; then set -x; fi

if [[ $EUID -ne 0 ]]; then
  echo 'Not root, re-running with sudo...' >&2
  exec sudo -- "$BASH" "$0" "$@"
fi

REPO_PATH=${REPO_PATH:-/home/jumpbox/kubernetes-the-hard-way}
CERT_DIR=${CERT_DIR:-$REPO_PATH/certs}
CA_CONF=${CA_CONF:-$CERT_DIR/ca.conf}
NODES=(node-0 node-1)
CONTROLPLANE=controlplane
API_SECTION=kube-api-server        # must match the [section] name in ca.conf
SECTIONS=(admin "${NODES[@]}" kube-proxy kube-scheduler kube-controller-manager "$API_SECTION" service-accounts)
# SANs the API server certificate must contain (add your controlplane IP if you like)
API_SANS=('DNS:controlplane.kubernetes.local' 'IP Address:127.0.0.1' 'IP Address:10.32.0.1')
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
FORCE=0 NEW_CA=0 COPY=1

declare -A EXPECT_CN=(
  [admin]=admin
  [kube-proxy]=system:kube-proxy
  [kube-scheduler]=system:kube-scheduler
  [kube-controller-manager]=system:kube-controller-manager
  [$API_SECTION]=kubernetes
  [service-accounts]=service-accounts
)

log()  { printf '%s [%s] %s\n' "$(date +%T)" "$1" "${*:2}" >&2; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
die()  { log ERROR "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [options]
  --force     regenerate every certificate (keeps the CA)
  --new-ca    also create a NEW CA (invalidates everything signed by the old one)
  --no-copy   generate and verify only, do not copy to the VMs
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

# the kubelet registers as the node's hostname, so the cert CN must match it
node_cn() {
  local h=$1 name
  if name=$(ssh "${SSH_OPTS[@]}" "root@$h" hostname 2>/dev/null) && [[ -n $name ]]; then
    printf 'system:node:%s' "${name,,}"
  else
    warn "cannot read hostname of $h over ssh, assuming node name '$h'"
    printf 'system:node:%s' "$h"
  fi
}

check_conf() {
  [[ -f $CA_CONF ]] || die "missing $CA_CONF"
  local s
  for s in "${SECTIONS[@]}"; do
    grep -qxF "[$s]" "$CA_CONF" || die "section [$s] not in ca.conf (list them: grep '^\[' $CA_CONF)"
  done
}

backup_existing() {
  compgen -G "$CERT_DIR/*.crt" >/dev/null || return 0
  local backup
  backup="$CERT_DIR/backup-$(date +%F-%H%M%S)"
  mkdir -p "$backup"
  find "$CERT_DIR" -maxdepth 1 -type f ! -name ca.conf -exec cp -a -t "$backup" {} +
  info "backed up existing files to $backup"
}

make_ca() {
  if [[ -s $CERT_DIR/ca.key && -s $CERT_DIR/ca.crt && $NEW_CA == 0 ]]; then
    info 'CA exists, keeping it'
    return
  fi
  warn 'creating a NEW CA: everything signed by the old CA becomes invalid'
  openssl genrsa -out "$CERT_DIR/ca.key" 4096
  openssl req -x509 -new -sha512 -noenc -key "$CERT_DIR/ca.key" -days 3653 \
    -config "$CA_CONF" -out "$CERT_DIR/ca.crt"
  chmod 600 "$CERT_DIR/ca.key"
}

# prints the problem and returns 1 when a cert is not good; prints nothing when good
check_cert() {
  local n=$1 crt="$CERT_DIR/$1.crt" key="$CERT_DIR/$1.key" cn san want
  [[ -s $crt && -s $key ]] || { echo 'missing files'; return 1; }
  openssl verify -CAfile "$CERT_DIR/ca.crt" "$crt" >/dev/null 2>&1 ||
    { echo 'not signed by the current CA'; return 1; }
  cmp -s <(openssl x509 -in "$crt" -noout -pubkey) <(openssl pkey -in "$key" -pubout) ||
    { echo 'private key does not match the certificate'; return 1; }
  cn=$(cn_of "$crt")
  [[ $cn == "${EXPECT_CN[$n]}" ]] ||
    { echo "wrong CN '$cn', expected '${EXPECT_CN[$n]}'"; return 1; }
  if [[ $n == "$API_SECTION" ]]; then
    san=$(openssl x509 -in "$crt" -noout -ext subjectAltName)
    for want in "${API_SANS[@]}"; do
      grep -qF -- "$want" <<<"$san" || { echo "SAN missing: $want"; return 1; }
    done
  fi
}

make_cert() {
  local n=$1 reason
  openssl genrsa -out "$CERT_DIR/$n.key" 4096
  openssl req -new -key "$CERT_DIR/$n.key" -sha256 \
    -config "$CA_CONF" -section "$n" -out "$CERT_DIR/$n.csr"
  openssl x509 -req -days 3653 -in "$CERT_DIR/$n.csr" -copy_extensions copyall \
    -sha256 -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial \
    -out "$CERT_DIR/$n.crt"
  chmod 600 "$CERT_DIR/$n.key"
  chmod 644 "$CERT_DIR/$n.crt"
  reason=$(check_cert "$n") || die "$n is still invalid after generation: $reason
  (for a node CN problem, set CN in the [$n] section of ca.conf to the expected value and rerun)"
}

install_on_nodes() {
  local h
  for h in "${NODES[@]}"; do
    if ! reachable "$h"; then warn "$h unreachable over ssh, skipping copy"; continue; fi
    ssh "${SSH_OPTS[@]}" "root@$h" 'mkdir -p /var/lib/kubelet'
    scp -q "${SSH_OPTS[@]}" "$CERT_DIR/ca.crt"  "root@$h:/var/lib/kubelet/ca.crt"
    scp -q "${SSH_OPTS[@]}" "$CERT_DIR/$h.crt"  "root@$h:/var/lib/kubelet/kubelet.crt"
    scp -q "${SSH_OPTS[@]}" "$CERT_DIR/$h.key"  "root@$h:/var/lib/kubelet/kubelet.key"
    ssh "${SSH_OPTS[@]}" "root@$h" 'chmod 600 /var/lib/kubelet/kubelet.key'
    info "installed kubelet certificates on $h"
  done
}

install_on_controlplane() {
  if ! reachable "$CONTROLPLANE"; then warn "$CONTROLPLANE unreachable, skipping copy"; return 0; fi
  ssh "${SSH_OPTS[@]}" "root@$CONTROLPLANE" 'mkdir -p /var/lib/kubernetes /etc/etcd'
  scp -q "${SSH_OPTS[@]}" \
    "$CERT_DIR/ca.crt" "$CERT_DIR/ca.key" \
    "$CERT_DIR/$API_SECTION.crt" "$CERT_DIR/$API_SECTION.key" \
    "$CERT_DIR/service-accounts.crt" "$CERT_DIR/service-accounts.key" \
    "root@$CONTROLPLANE:/var/lib/kubernetes/"
  scp -q "${SSH_OPTS[@]}" \
    "$CERT_DIR/ca.crt" "$CERT_DIR/$API_SECTION.crt" "$CERT_DIR/$API_SECTION.key" \
    "root@$CONTROLPLANE:/etc/etcd/"
  ssh "${SSH_OPTS[@]}" "root@$CONTROLPLANE" 'chmod 600 /var/lib/kubernetes/*.key /etc/etcd/*.key'
  info "installed control plane certificates on $CONTROLPLANE"
}

summary() {
  local n
  printf '\n%-26s %-44s %s\n' NAME CN EXPIRES
  for n in ca "${SECTIONS[@]}"; do
    printf '%-26s %-44s %s\n' "$n" "$(cn_of "$CERT_DIR/$n.crt")" \
      "$(openssl x509 -in "$CERT_DIR/$n.crt" -noout -enddate | cut -d= -f2)"
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0 ;;
      --force)   FORCE=1 ;;
      --new-ca)  NEW_CA=1; FORCE=1 ;;
      --no-copy) COPY=0 ;;
      *)         die "unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require openssl ssh scp awk cmp find
  [[ -d $CERT_DIR ]] || die "missing directory $CERT_DIR"
  check_conf

  local n reason
  for n in "${NODES[@]}"; do EXPECT_CN[$n]=$(node_cn "$n"); done

  backup_existing
  make_ca

  for n in "${SECTIONS[@]}"; do
    if (( FORCE )); then
      reason=forced
    elif reason=$(check_cert "$n"); then
      info "ok: $n"
      continue
    fi
    info "generating $n ($reason)"
    make_cert "$n"
  done

  summary
  if (( COPY )); then
    install_on_nodes
    install_on_controlplane
  fi
  info 'certificates done'
}

main "$@"
