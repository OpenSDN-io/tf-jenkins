#!/bin/bash -eEx

set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

export OS_NETWORK_ID=$(openstack network show $OS_NETWORK -c id -f value)

if [[ ${IMAGE_TYPE^^} == 'RHCOS45' ]]; then
  echo "INFO: prepared image doesn't require special preparation - it was created with base image. Exiting"
  exit
fi

# install plugin
# TODO: move it to setup for proper user
packer plugins install github.com/hashicorp/openstack

for i in "${!OS_IMAGE_USERS[@]}"; do
  if [[ ${IMAGE_TYPE^^} == 'ALL' && ${IMAGE_TYPE^^} == 'RHCOS45' ]]; then
    # skip preparation for RHCOS image
    continue
  fi
  if [[ ${IMAGE_TYPE^^} != 'ALL' && ${IMAGE_TYPE^^} != ${i^^} ]]; then
    continue
  fi

  echo "INFO: pack image for $i and upload it"
  packer build -machine-readable -var "os_image=${i,,}" -var "ssh_user=${OS_IMAGE_USERS[$i]}" -debug \
      ${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/packer/openstack.json
  if ! OLD_IMAGES=$(openstack image list --tag prepared-${i,,} -c Name -f value | sort -nr | tail -n +4) ; then
    # python-openstackclient has a bug - it doesn't allow to use '--tag' param even it has it in help
    OLD_IMAGES=$(openstack image list -c Name -f value | grep "prepared-${i,,}" | sort -nr | tail -n +4)
  fi
  for o in $OLD_IMAGES ; do
    echo "INFO: remove old image $o"
    openstack image delete $o
  done
done
