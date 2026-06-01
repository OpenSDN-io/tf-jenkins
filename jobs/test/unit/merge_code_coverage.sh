#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname "$my_file")"

source "$my_dir/definitions"

function run_merge_over_ssh() {
  local script="run_merge_coverage.sh"

  cat <<EOF >"$WORKSPACE/$script"
#!/bin/bash -eE
set -o pipefail
[ "\${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
export CONTRAIL_DEPLOY_REGISTRY=0

export CONTAINER_REGISTRY="${CONTAINER_REGISTRY}"
export DEVENV_TAG="${DEVENV_TAG}"
export LOGS_URL="${LOGS_URL}"
export STREAM="${STREAM}"
export CONTRAIL_DIR=""

cd src/opensdn-io/tf-dev-env
./run.sh merge_coverage
EOF

  chmod a+x "$WORKSPACE/$script"

  ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
  rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/$script} $IMAGE_SSH_USER@$instance_ip:./
  local res=0
  eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./$script || res=1
  return "$res"
}

if ! run_merge_over_ssh; then
  echo "ERROR: coverage merge failed"
  exit 1
fi

echo "INFO: coverage merge finished successfully"
