#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [[ -n "$PUBLISH_TAGS" ]]; then
  tags="$PUBLISH_TAGS"
else
  tag_suffix=""
  if [[ "${STABLE,,}" == "true" ]] ; then
    tag_suffix="-stable"
  fi
  if [[ "$GERRIT_BRANCH" != "master" ]]; then
    tag_prefix="${GERRIT_BRANCH}-"
  fi
  tags="$tag_prefix$(date --utc +"%Y-%m-%d")${tag_suffix}"
  tags+=",${tag_prefix}latest${tag_suffix}"
fi

scp -i $WORKER_SSH_KEY $SSH_OPTIONS $my_dir/publish.sh $IMAGE_SSH_USER@$instance_ip:./
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

echo "INFO: Prepare worker"
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
export WORKSPACE=\$HOME
[ "${DEBUG,,}" == "true" ] && set -x
export PATH=\$PATH:/usr/sbin
export DEBUG=$DEBUG
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
./src/opensdn-io/tf-dev-env/common/setup_docker.sh

# to get DISTRO env variable
source ./src/opensdn-io/tf-dev-env/common/common.sh
# setup additional packages
if [ x"\$DISTRO" == x"ubuntu" ]; then
  export DEBIAN_FRONTEND=noninteractive
  sudo -E apt-get install -y jq curl
else
  sudo yum -y install epel-release
  sudo yum install -y jq curl
fi

EOF

echo "INFO: Publish started"
export PUBLISH_REGISTRY=${PUBLISH_REGISTRY:-'opensdn'}
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
export WORKSPACE=\$HOME
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX
export DEVENV_IMAGE_NAME=tf-dev-sandbox
export PUBLISH_REGISTRY=$PUBLISH_REGISTRY
export PUBLISH_REGISTRY_USER=$DOCKERHUB_USERNAME
export PUBLISH_REGISTRY_PASSWORD=$DOCKERHUB_PASSWORD
export PUBLISH_TAGS=$tags
sudo -E ./publish.sh
EOF
echo "INFO: Publish containers done"
