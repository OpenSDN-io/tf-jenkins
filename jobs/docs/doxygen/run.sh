#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# suppose that all required infra already up

echo "INFO: docs started. ENVIRONMENT_OS=$ENVIRONMENT_OS LINUX_DISTR=$LINUX_DISTR TARGET=$TARGET"

function run_over_ssh() {
  local res=0
  local script="run-$STAGE-$TARGET.sh"
cat <<EOF >$WORKSPACE/$script
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

export GERRIT_URL=${GERRIT_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}
export GERRIT_PROJECT=${GERRIT_PROJECT}

# devenftag is passed from parent fetch-sources job
export DEVENV_TAG=$DEVENV_TAG

cd src/opensdn-io/tf-dev-env

./run.sh $@

# TODO: push to gerrit

EOF

  chmod a+x $WORKSPACE/$script

  ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
  rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/$script} $IMAGE_SSH_USER@$instance_ip:./
  # run this via eval due to special symbols in ssh_cmd
  eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./$script || res=1
  return $res
}

if ! run_over_ssh $TARGET ; then
  echo "ERROR: docs failed"
  exit 1
fi

echo "INFO: docs finished successfully"
