#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

ENV_FILE=${ENV_FILE:-"$WORKSPACE/stackrc.$JOB_NAME.env"}
source $ENV_FILE

cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin
echo INFO: Sanity logs path content
ls -la /home/centos/src/tungstenfabric/tf-test/contrail-sanity/contrail-test-runs/ || /bin/true
cd src/tungstenfabric/tf-devstack/k8s_manifests
ORCHESTRATOR=$ORCHESTRATOR ./run.sh logs
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:logs.tgz $WORKSPACE/logs.tgz
pushd $WORKSPACE || /bin/true
tar -xzf logs.tgz

# Collect sanity logs from worker
mkdir -p logs/sanity
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $IMAGE_SSH_USER@$instance_ip:$SANITY_LOGS_PATH $WORKSPACE/logs/sanity/ || /bin/true

FULL_LOGS_PATH="${LOGS_PATH}/${JOB_LOGS_PATH}"
ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS $LOGS_HOST_USERNAME@$LOGS_HOST "mkdir -p $FULL_LOGS_PATH"
rsync -a -e "ssh -i $LOGS_HOST_SSH_KEY $SSH_OPTIONS" $WORKSPACE/logs $LOGS_HOST_USERNAME@$LOGS_HOST:$FULL_LOGS_PATH
rm -rf $WORKSPACE/logs
popd
