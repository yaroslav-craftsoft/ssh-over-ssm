#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

die () { echo "[${0##*/}] $*" >&2; exit 1; }

[[ $# -ne 3 ]] && die "usage: ${0##*/} <instance-id> <ssh user> <pub key path>"
[[ ! $1 =~ ^i-([0-9a-f]{8,})$ ]] && die "error: invalid instance-id"
[[ ! -f $3 ]] && die "error: pub key file does not exist"

SSH_PUB_KEY=$(cat "$3")

# command to put our public key on the remote server (user must already exist)
ssm_cmd=$(cat <<EOF
  "u=\$(getent passwd ${2}) && x=\$(echo \$u |cut -d: -f6) || exit 1
  [ ! -d \${x}/.ssh ] && install -d -m700 -o${2} \${x}/.ssh
  grep '${SSH_PUB_KEY}' \${x}/.ssh/authorized_keys && exit 0
  printf '${SSH_PUB_KEY}\n'|tee -a \${x}/.ssh/authorized_keys || exit 1
  (sleep 15 && sed -i '\|${SSH_PUB_KEY}|d' \${x}/.ssh/authorized_keys &) >/dev/null 2>&1"
EOF
)

# execute the command using aws ssm send-command
command_id=$(aws ssm send-command \
  --instance-ids "$1" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="${ssm_cmd}" \
  --comment "temporary ssm ssh access" \
  --output text \
  --query Command.CommandId)

# wait for successful send-command execution
aws ssm wait command-executed --instance-id "$1" --command-id "${command_id}"

# start ssh session over ssm
aws ssm start-session --document-name AWS-StartSSHSession --target "$1"
