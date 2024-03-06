#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

echo "INFO: Test $TARGET started  $(date)"

case $TARGET in
  "sanity" )
    script="src/opensdn-io/tf-dev-test/tf-sanity/run.sh"
    ;;
  "deployment" )
    script="src/opensdn-io/tf-dev-test/deployment-test/run.sh"
    ;;
  "smoke" )
    script="src/opensdn-io/tf-dev-test/smoke-test/run.sh"
    ;;
  "tempest" )
    script="src/opensdn-io/tf-dev-test/tempest/run.sh"
    ;;
  *)
    echo "Variable TARGET is not set or incorrect"
    exit 1
    ;;
esac

cat << EOF > $WORKSPACE/functional-test-$TARGET.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR

export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG$TAG_SUFFIX"

export CONTAINER_REGISTRY_ORIGINAL="$CONTAINER_REGISTRY_ORIGINAL"
export DEPLOYER_CONTAINER_REGISTRY_ORIGINAL="$DEPLOYER_CONTAINER_REGISTRY_ORIGINAL"
export CONTRAIL_CONTAINER_TAG_ORIGINAL="$CONTRAIL_CONTAINER_TAG_ORIGINAL$TAG_SUFFIX"
export CONTRAIL_DEPLOYER_CONTAINER_TAG_ORIGINAL="$CONTRAIL_DEPLOYER_CONTAINER_TAG_ORIGINAL$TAG_SUFFIX"

export SSL_ENABLE=$SSL_ENABLE
export TF_TEST_IMAGE="$TF_TEST_IMAGE"
export TF_DEPLOYMENT_TEST_IMAGE="$TF_DEPLOYMENT_TEST_IMAGE"
export PATH=\$PATH:/usr/sbin
export DEPLOYMENT_TEST_TAGS="$DEPLOYMENT_TEST_TAGS"
export LEGACY_ANALYTICS_ENABLE="$LEGACY_ANALYTICS_ENABLE"
$script
EOF
chmod a+x $WORKSPACE/functional-test-$TARGET.sh

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/functional-test-$TARGET.sh} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./functional-test-$TARGET.sh || res=1

echo "INFO: Test $TARGET finished  $(date)"
exit $res
