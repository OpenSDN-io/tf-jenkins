#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

script="update.sh"
cat <<EOF > $WORKSPACE/$script
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export TPC_REPO_USER=$TPC_REPO_USER
export TPC_REPO_PASS=$TPC_REPO_PASS
export REPO_SOURCE=http://nexus.$SLAVE_REGION.$CI_DOMAIN/repository
export DOCKER_MIRROR=tf-mirrors.$SLAVE_REGION.$CI_DOMAIN:5005

$update_func
EOF

rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" {$WORKSPACE/src,$WORKSPACE/$script,$my_dir/update*.sh} $IMAGE_SSH_USER@$instance_ip:./

if [[ "$ARTEFACT_TYPE" == 'THIRD_PARTY_PACKAGES' ]] ; then
  update_func="./update_third_party_packages.sh"
elif [[ "$ARTEFACT_TYPE" == 'SANITY_IMAGES' ]] ; then
  update_func="./update_sanity_images.sh"
elif [[ "$ARTEFACT_TYPE" == 'THIRD_PARTY_DOCKER_IMAGES' ]] ; then
  update_func="./update_third_party_docker_images.sh"
else
  echo "ERROR: unknown artefact type $ARTEFACT_TYPE"
  exit 1
fi

echo "INFO: Update artefacts started  $(date)"
eval ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip ./$script || res=1

echo "INFO: Update artefacts finished  $(date)"
exit $res
