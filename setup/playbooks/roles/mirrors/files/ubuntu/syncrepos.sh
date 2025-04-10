#!/bin/bash -e

MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

mkdir -p ${MIRRORDIR}/ubuntu/${DATE}
cd ${MIRRORDIR}/ubuntu

sed -i "s|%MIRRORDIR%|${MIRRORDIR}/ubuntu/${DATE}|" /etc/apt/mirror.list
sed -i "s|%CI_DOMAIN%|${CI_DOMAIN}|" /etc/apt/sources.list
sed -i "s|%SLAVE_REGION%|${SLAVE_REGION}|" /etc/apt/sources.list
/apt-mirror-20

mkdir -p ${DATE}/lxd
pushd ${DATE}/lxd

for distro in "focal" "jammy" "noble"; do
  rm -f $distro-server-cloudimg-amd64*
  wget -nv https://cloud-images.ubuntu.com/$distro/current/$distro-server-cloudimg-amd64-lxd.tar.xz
  wget -nv https://cloud-images.ubuntu.com/$distro/current/$distro-server-cloudimg-amd64-root.tar.xz
done

popd

rm -f stage
ln -s ${DATE} stage