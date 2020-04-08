#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Deploy platform for $JOB_NAME"

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export RHEL_OPENSHIFT_REGISTRY=$RHEL_OPENSHIFT_REGISTRY
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export PATH=\$PATH:/usr/sbin
sudo setenforce 0
cd src/tungstenfabric/tf-devstack/openshift
ORCHESTRATOR=$ORCHESTRATOR ./run.sh platform
EOF

echo "INFO: Deploy platform finished"
exit $res
