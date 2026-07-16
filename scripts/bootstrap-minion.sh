#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bootstrap-minion.sh --master <host> [options]

Install/configure salt-minion for the redsalt-master environment.

Required:
  --master <host>              Salt master DNS name or IP address

Options:
  --id <minion-id>             Stable minion ID (default: hostname -f, then hostname)
  --roles <csv>                Inventory roles to write to grains (default: base)
  --environment <name>         redsalt environment grain (default: prd)
  --saltenv <name>             Salt file environment (default: base)
  --pillarenv <name>           Salt pillar environment (default: base)
  --master-finger <finger>     Optional Salt master public key fingerprint pin
  --install-method <method>    apt, bootstrap, or none (default: apt)
  --no-start                   Do not enable/restart salt-minion after writing files
  -h, --help                   Show this help
USAGE
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: run as root or via sudo" >&2
    exit 1
  fi
}

hostname_default() {
  hostname -f 2>/dev/null || hostname
}

MASTER=""
MINION_ID="$(hostname_default)"
ROLES="base"
ENVIRONMENT="prd"
SALTENV="base"
PILLARENV="base"
MASTER_FINGER=""
INSTALL_METHOD="apt"
START_SERVICE=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --master) MASTER="${2:-}"; shift 2 ;;
    --id) MINION_ID="${2:-}"; shift 2 ;;
    --roles) ROLES="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT="${2:-}"; shift 2 ;;
    --saltenv) SALTENV="${2:-}"; shift 2 ;;
    --pillarenv) PILLARENV="${2:-}"; shift 2 ;;
    --master-finger) MASTER_FINGER="${2:-}"; shift 2 ;;
    --install-method) INSTALL_METHOD="${2:-}"; shift 2 ;;
    --no-start) START_SERVICE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$MASTER" ]; then
  echo "ERROR: --master is required" >&2
  usage >&2
  exit 2
fi
if [ -z "$MINION_ID" ]; then
  echo "ERROR: --id resolved to an empty minion id" >&2
  exit 2
fi
case "$INSTALL_METHOD" in
  apt|bootstrap|none) ;;
  *) echo "ERROR: --install-method must be apt, bootstrap, or none" >&2; exit 2 ;;
esac

require_root

install_minion_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y salt-minion
}

install_minion_bootstrap() {
  tmp_script="$(mktemp)"
  curl -fsSL https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh -o "$tmp_script"
  sh "$tmp_script" -P stable
  rm -f "$tmp_script"
}

if ! command -v salt-minion >/dev/null 2>&1; then
  case "$INSTALL_METHOD" in
    apt) install_minion_apt ;;
    bootstrap) install_minion_bootstrap ;;
    none) echo "salt-minion not installed and --install-method none selected" >&2 ;;
  esac
fi

install -d -m 0755 /etc/salt/minion.d
cat > /etc/salt/minion.d/99-redsalt.conf <<EOF
# Managed by redsalt-minion/scripts/bootstrap-minion.sh
master: ${MASTER}
id: ${MINION_ID}
saltenv: ${SALTENV}
pillarenv: ${PILLARENV}
startup_states: ''
random_reauth_delay: 60
recon_default: 1000
recon_max: 59000
recon_randomize: True
EOF

if [ -n "$MASTER_FINGER" ]; then
  printf "master_finger: '%s'\n" "$MASTER_FINGER" >> /etc/salt/minion.d/99-redsalt.conf
fi

install -d -m 0755 /etc/salt
{
  printf 'redsalt:\n'
  printf '  environment: %s\n' "$ENVIRONMENT"
  printf '  roles:\n'
  old_ifs="$IFS"
  IFS=','
  for role in $ROLES; do
    role_trimmed="$(printf '%s' "$role" | tr -d '[:space:]')"
    [ -n "$role_trimmed" ] && printf '    - %s\n' "$role_trimmed"
  done
  IFS="$old_ifs"
  printf '  managed_by: redsalt-minion\n'
} > /etc/salt/grains
chmod 0644 /etc/salt/minion.d/99-redsalt.conf /etc/salt/grains

if [ "$START_SERVICE" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
  systemctl enable salt-minion
  systemctl restart salt-minion
fi

cat <<EOF
redsalt minion configured
  id: ${MINION_ID}
  master: ${MASTER}
  roles grain: ${ROLES}
  config: /etc/salt/minion.d/99-redsalt.conf
  grains: /etc/salt/grains

Next on the Salt master:
  salt-key -L
  salt-key -a '${MINION_ID}'
  add pillar/minions/${MINION_ID}.sls and pillar/top.sls entry in redsalt-master
EOF
