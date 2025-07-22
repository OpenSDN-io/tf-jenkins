#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

if [[ -z ${TPC_REPO_USER} || -z ${TPC_REPO_PASS} ]] ; then
  echo "ERROR: Please define variables TPC_REPO_USER and TPC_REPO_PASS. Exiting..."
  exit 1
fi

sudo yum install -y wget curl

rm -rf sanity_images
mkdir -p sanity_images
pushd sanity_images

# this archive already has 'images' prefix in file's path
wget -nv https://tf-ci.hb.ru-msk.vkcs.cloud/images.tgz
tar -xvf images.tgz
rm images.tgz
# images/converts already created by untar cmd
wget -nv https://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img -O images/converts/cirros-0.4.0-x86_64-disk.img

for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/$file
done

popd
