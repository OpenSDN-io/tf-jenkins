#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"



rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$my_dir/*} $IMAGE_SSH_USER@$instance_ip:./

export CONTAINER_REGISTRY=${CONTAINER_REGISTRY:-"tf-mirrors.progmaticlab.com:5005"}

echo "INFO: update rhosp images started"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
#!/bin/bash -e
echo "export RHEL_USER=$RHEL_USER" > rhel-account
echo "export RHEL_PASSWORD=$RHEL_PASSWORD" >> rhel-account

[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
./src/tungstenfabric/tf-dev-env/common/setup_docker.sh


./update_${OPENSTACK_VERSION}_docker_images.sh
EOF
echo "INFO: Update ${OPENSTACK_VERSION} docker images finished"
