#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# Note: Base images centos8 rhel7 rhel8 must be updated manually.
# The image name should follow the example: base-rhel8-202012321201.

# rhel8 - https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.4/x86_64/product-software

date_suffix=$(date +%Y%m%d%H%M)

images=''

# Get images
if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'CENTOS7' ]]; then
  echo "INFO: download centos7 from centos.org"
  curl -LOs "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz"
  echo "INFO: decompress centos7"
  xz --decompress CentOS-7-x86_64-GenericCloud.qcow2.xz
  echo "INFO: upload centos7 to openstack"
  openstack image create --disk-format qcow2 --tag centos7 --file CentOS-7-x86_64-GenericCloud.qcow2 base-centos7-$date_suffix
  rm -f CentOS-7-x86_64-GenericCloud.qcow2*
  images="$images base-centos7-$date_suffix"
fi

if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'CENTOS8' ]]; then
  echo "INFO: download centos8 from centos.org"
  curl -LOs "https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2"
  echo "INFO: upload centos8 to openstack"
  openstack image create --disk-format qcow2 --tag centos8 --file CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2 base-centos8-$date_suffix
  rm -f CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2
  images="$images base-centos8-$date_suffix"
fi

if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'UBUNTU20' ]]; then
  echo "INFO: download ubuntu20 from cloud-images"
  curl -LOs "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  curl -Ls "https://cloud-images.ubuntu.com/focal/current/SHA256SUMS" -o ubuntu20-SHA256SUMS
  sha256sum -c ubuntu20-SHA256SUMS --ignore-missing --status
  echo "INFO: upload ubuntu20 to openstack"
  openstack image create --disk-format qcow2 --tag ubuntu20 --file focal-server-cloudimg-amd64.img base-ubuntu20-$date_suffix
  rm -f focal-server-cloudimg-amd64.img
  images="$images base-ubuntu20-$date_suffix"
fi

if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'UBUNTU22' ]]; then
  echo "INFO: download ubuntu22 from cloud-images"
  curl -LOs "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  curl -Ls "https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS" -o ubuntu22-SHA256SUMS
  sha256sum -c ubuntu22-SHA256SUMS --ignore-missing --status
  echo "INFO: upload ubuntu22 to openstack"
  openstack image create --disk-format qcow2 --tag ubuntu22 --file jammy-server-cloudimg-amd64.img base-ubuntu22-$date_suffix
  rm -f jammy-server-cloudimg-amd64.img
  images="$images base-ubuntu22-$date_suffix"
fi

if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'ROCKY9' ]]; then
  # 9.1 has gcc 11.2.1 which is only available for centos7 to build the kernel module
  # echo "INFO: download rocky linux 9.1 from download.rockylinux.org"
  # curl -LOs "https://dl.rockylinux.org/vault/rocky/9.1/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  # curl -Ls "https://dl.rockylinux.org/vault/rocky/9.1/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2.CHECKSUM" -o rocky9-SHA256SUMS

  # 9.3 links
  echo "INFO: download rocky linux 9.3 from download.rockylinux.org"
  curl -LOs "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
  curl -Ls "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2.CHECKSUM" -o rocky9-SHA256SUMS

  sha256sum -c rocky9-SHA256SUMS --ignore-missing --status

  echo "INFO: upload rocky9 to openstack"
  openstack image create --disk-format qcow2 --tag rocky9 --file Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 base-rocky9-$date_suffix
  rm -f Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
  images="$images base-rocky9-$date_suffix"
fi

if [[ ${IMAGE_TYPE^^} == 'ALL' || ${IMAGE_TYPE^^} == 'ROCKY92' ]]; then
  # 9.2 links
  echo "INFO: download rocky linux 9.2 from dl.rockylinux.org"
  curl -LOs "https://dl.rockylinux.org/vault/rocky/9.2/images/x86_64/Rocky-9-GenericCloud-Base-9.2-20230513.0.x86_64.qcow2"
  curl -Ls "https://dl.rockylinux.org/vault/rocky/9.2/images/x86_64/Rocky-9-GenericCloud-Base-9.2-20230513.0.x86_64.qcow2.CHECKSUM" -o rocky92-SHA256SUMS

  sha256sum -c rocky92-SHA256SUMS --ignore-missing --status

  echo "INFO: upload rocky9 to openstack"
  openstack image create --disk-format qcow2 --tag rocky92 --file Rocky-9-GenericCloud-Base-9.2-20230513.0.x86_64.qcow2 base-rocky92-$date_suffix
  rm -f Rocky-9-GenericCloud-Base-9.2-20230513.0.x86_64.qcow2
  images="$images base-rocky92-$date_suffix"
fi

sleep 10
printf "\n\nINFO: uploaded images"
for image in $images ; do
  openstack image show $image
done
printf "\n\n\n"

# Remove previous images
# this code leaves 4 latest images - so it can be run always
echo "INFO: remove previous images"
IMAGES_LIST=$(openstack image list -c Name -f value | grep "^base-")
OS_NAMES=$(echo "$IMAGES_LIST" | awk -F "-" '{print $2}' | sort | uniq)

for o in $OS_NAMES; do
  OLD_IMAGES=$(echo "$IMAGES_LIST" | grep "$o" | sort -nr | tail -n +4)
  for i in $OLD_IMAGES; do
    echo "INFO: remove $i"
    openstack image delete $i
  done
done
