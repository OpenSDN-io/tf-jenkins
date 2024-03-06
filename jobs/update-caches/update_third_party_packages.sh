#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

if [[ -z ${TPC_REPO_USER} || -z ${TPC_REPO_PASS} ]] ; then
  echo "ERROR: Please define variables TPC_REPO_USER and TPC_REPO_PASS. Exiting..."
  exit 1
fi

sudo yum install -y wget curl gcc python3 python3-setuptools python3-devel python3-lxml
curl -fsS --retry 3 --retry-delay 10 https://bootstrap.pypa.io/pip/3.6/get-pip.py | sudo python3
sudo python3 -m pip install urllib3

# tf-container-build cache

export CACHE_DIR="$(pwd)/containers_cache"
echo "INFO: download cache for tf-container-builder/containers/populate-cache.sh"
./src/opensdn-io/tf-container-builder/containers/populate-cache.sh
echo "INFO: download cache for tf-dev-env/container/populate-cache.sh"
./src/opensdn-io/tf-dev-env/container/populate-cache.sh

echo "INFO: Upload containers cache files"
pushd $CACHE_DIR
IFS=$'\n'
for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T "$file" "$REPO_SOURCE/external-web-cache/$file"
done
popd

# tf-third-party and tf-webui-third-party caches

function update_third_party_cache() {
  local folder=$1
  local xmlfile=$2
  local cache_folder=$3

  echo "INFO: update cache for $folder/$xmlfile"
  mkdir -p $cache_folder
  pushd $folder
  python3 populate_cache.py $cache_folder $xmlfile
  popd
}

CACHE_DIR="$(pwd)/third_party"
update_third_party_cache src/opensdn-io/tf-third-party packages.xml $CACHE_DIR
update_third_party_cache src/opensdn-io/tf-webui-third-party packages.xml $CACHE_DIR
update_third_party_cache src/opensdn-io/tf-webui-third-party packages_dev.xml $CACHE_DIR

echo "INFO: Upload third-party cached files"
pushd $CACHE_DIR
for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  # ontrail-third-party already in path of downloaded files
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/$file
done
popd

unset IFS
# tpc binary cache

CACHE_DIR="$(pwd)/tpc-binary"
mkdir -p $CACHE_DIR
pushd $CACHE_DIR

# archived packages
kernels="
  https://vault.centos.org/7.6.1810/updates/x86_64/Packages/kernel-3.10.0-957.12.2.el7.x86_64.rpm
  https://vault.centos.org/7.6.1810/updates/x86_64/Packages/kernel-devel-3.10.0-957.12.2.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/os/x86_64/Packages/kernel-3.10.0-1062.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/os/x86_64/Packages/kernel-devel-3.10.0-1062.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.4.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.4.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.9.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.9.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-3.10.0-1062.12.1.el7.x86_64.rpm
  https://vault.centos.org/7.7.1908/updates/x86_64/Packages/kernel-devel-3.10.0-1062.12.1.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/os/x86_64/Packages/kernel-3.10.0-1127.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/os/x86_64/Packages/kernel-devel-3.10.0-1127.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/updates/x86_64/Packages/kernel-3.10.0-1127.18.2.el7.x86_64.rpm
  https://vault.centos.org/7.8.2003/updates/x86_64/Packages/kernel-devel-3.10.0-1127.18.2.el7.x86_64.rpm
  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-4.18.0-193.28.1.el8_2.x86_64.rpm
  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-core-4.18.0-193.28.1.el8_2.x86_64.rpm
  https://vault.centos.org/8.2.2004/BaseOS/x86_64/os/Packages/kernel-devel-4.18.0-193.28.1.el8_2.x86_64.rpm
"

# current packages - should be taken from archive after new release
kernels+="
  http://mirror.centos.org/centos/7/updates/x86_64/Packages/kernel-3.10.0-1160.53.1.el7.x86_64.rpm
  http://mirror.centos.org/centos/7/updates/x86_64/Packages/kernel-devel-3.10.0-1160.53.1.el7.x86_64.rpm
  http://mirror.centos.org/centos/7/updates/x86_64/Packages/kernel-3.10.0-1160.25.1.el7.x86_64.rpm
  http://mirror.centos.org/centos/7/updates/x86_64/Packages/kernel-devel-3.10.0-1160.25.1.el7.x86_64.rpm
  https://vault.centos.org/8.4.2105/BaseOS/x86_64/os/Packages/kernel-4.18.0-305.12.1.el8_4.x86_64.rpm
  https://vault.centos.org/8.4.2105/BaseOS/x86_64/os/Packages/kernel-core-4.18.0-305.12.1.el8_4.x86_64.rpm
  https://vault.centos.org/8.4.2105/BaseOS/x86_64/os/Packages/kernel-devel-4.18.0-305.12.1.el8_4.x86_64.rpm
"

# rocky9 kernel for 9.1(gcc 11.2.1)
kernels+="
  https://dl.rockylinux.org/vault/rocky/9.1/BaseOS/x86_64/os/Packages/k/kernel-5.14.0-162.23.1.el9_1.x86_64.rpm
  https://dl.rockylinux.org/vault/rocky/9.1/BaseOS/x86_64/os/Packages/k/kernel-core-5.14.0-162.23.1.el9_1.x86_64.rpm
  https://dl.rockylinux.org/vault/rocky/9.1/BaseOS/x86_64/os/Packages/k/kernel-modules-5.14.0-162.23.1.el9_1.x86_64.rpm
  https://dl.rockylinux.org/vault/rocky/9.1/AppStream/x86_64/os/Packages/k/kernel-devel-5.14.0-162.23.1.el9_1.x86_64.rpm
"

# rocky9 kernel for 9.3(gcc 11.4.1)
# TODO: maybe use images from https://dl.rockylinux.org/vault/rocky or https://download.rockylinux.org/pub/rocky
kernels+="
  https://cbs.centos.org/kojifiles/packages/kernel/5.14.0/362.el9s/x86_64/kernel-5.14.0-362.el9s.x86_64.rpm
  https://cbs.centos.org/kojifiles/packages/kernel/5.14.0/362.el9s/x86_64/kernel-core-5.14.0-362.el9s.x86_64.rpm
  https://cbs.centos.org/kojifiles/packages/kernel/5.14.0/362.el9s/x86_64/kernel-modules-5.14.0-362.el9s.x86_64.rpm
  https://cbs.centos.org/kojifiles/packages/kernel/5.14.0/362.el9s/x86_64/kernel-modules-core-5.14.0-362.el9s.x86_64.rpm
  https://cbs.centos.org/kojifiles/packages/kernel/5.14.0/362.el9s/x86_64/kernel-devel-5.14.0-362.el9s.x86_64.rpm
"

for kernel in $kernels ; do
  wget -nv --no-check-certificate $kernel
done

wget -nv -O - https://tf-ci.hb.ru-msk.vkcs.cloud/tpc.tar | tar -xv

for file in $(find . -type f) ; do
  echo "INFO: upload $file"
  curl -fsS --user "${TPC_REPO_USER}:${TPC_REPO_PASS}" --ftp-create-dirs -T $file $REPO_SOURCE/yum-tpc-binary/$file
done
popd
