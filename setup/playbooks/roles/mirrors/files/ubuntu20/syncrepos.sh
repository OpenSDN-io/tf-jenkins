#!/bin/bash -e

MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

mkdir -p ${MIRRORDIR}/ubuntu20/${DATE}
cd ${MIRRORDIR}/ubuntu20

sed -i "s|%MIRRORDIR%|${MIRRORDIR}/ubuntu20/${DATE}|" /etc/apt/mirror.list
sed -i "s|%CI_DOMAIN%|${CI_DOMAIN}|" /etc/apt/sources.list
sed -i "s|%SLAVE_REGION%|${SLAVE_REGION}|" /etc/apt/sources.list
apt-mirror

mkdir -p ${DATE}/lxd
pushd ${DATE}/lxd
wget -nv https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-lxd.tar.xz
wget -nv https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-root.tar.xz
popd

rm -f stage
ln -s ${DATE} stage
