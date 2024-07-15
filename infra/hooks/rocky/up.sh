#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$WORKSPACE/global.env"
source "$WORKSPACE/stackrc.$JOB_NAME.env" || /bin/true
source "${WORKSPACE}/deps.${JOB_NAME}.${JOB_RND}.env" || /bin/true
source "${WORKSPACE}/vars.${JOB_NAME}.${JOB_RND}.env" || /bin/true

ssh_cmd="ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}"

cat $my_dir/../../mirrors/mirror-pip.conf | envsubst > "$WORKSPACE/mirror-pip.conf"
rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-pip.conf" ${IMAGE_SSH_USER}@${instance_ip}:./pip.conf
cat $my_dir/../../mirrors/mirror-docker-daemon.json | envsubst > "$WORKSPACE/mirror-docker-daemon.json"
rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-docker-daemon.json" ${IMAGE_SSH_USER}@${instance_ip}:./docker-daemon.json

cat <<EOF | $ssh_cmd $IMAGE_SSH_USER@$instance_ip
sudo cp -f ./pip.conf /etc/pip.conf
sudo mkdir -p /etc/docker/
sudo cp -f ./docker-daemon.json /etc/docker/daemon.json
#sudo kill -SIGHUP $(pidof dockerd)
EOF

$ssh_cmd $IMAGE_SSH_USER@$instance_ip "grep VERSION_ID /etc/os-release" 2>/dev/null >"$WORKSPACE/os-release-$instance_ip"
source "$WORKSPACE/os-release-$instance_ip"

# TODO: create rocky9 mirrors and uncomment this with updates
# if [ -f $my_dir/../../mirrors/centos${VERSION_ID}-environment ]; then
#   echo "INFO: copy additional environment to host"
#   cat $my_dir/../../mirrors/centos${VERSION_ID}-environment | envsubst > "$WORKSPACE/centos${VERSION_ID}-environment"
#   rsync -a -e "$ssh_cmd" "$WORKSPACE/centos${VERSION_ID}-environment" ${IMAGE_SSH_USER}@${instance_ip}:./centos${VERSION_ID}-environment
#   $ssh_cmd $IMAGE_SSH_USER@$instance_ip "cat centos${VERSION_ID}-environment | sudo tee -a /etc/environment"
# fi

# if [ -f $my_dir/../../mirrors/mirror-base-centos${VERSION_ID}.repo ]; then
#   echo "INFO: copy mirror-base-centos${VERSION_ID}.repo to host"
#   cat $my_dir/../../mirrors/mirror-base-centos${VERSION_ID}.repo | envsubst > "$WORKSPACE/mirror-base-centos${VERSION_ID}.repo"
#   rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-base-centos${VERSION_ID}.repo" ${IMAGE_SSH_USER}@${instance_ip}:./mirror-base-centos${VERSION_ID}.repo
#   $ssh_cmd $IMAGE_SSH_USER@$instance_ip "sudo rm -f /etc/yum.repos.d/*; sudo cp mirror-base-centos${VERSION_ID}.repo /etc/yum.repos.d/"
# fi

# # must be after sync of mirror-base-centos as it does clea of /etc/yum.repos.d/*
# if [ -f $my_dir/../../mirrors/mirror-epel${VERSION_ID}.repo ]; then
#   echo "INFO: copy mirror-epel${VERSION_ID}.repo to host"
#   cat $my_dir/../../mirrors/mirror-epel${VERSION_ID}.repo | envsubst > "$WORKSPACE/mirror-epel${VERSION_ID}.repo"
#   rsync -a -e "$ssh_cmd" "$WORKSPACE/mirror-epel${VERSION_ID}.repo" ${IMAGE_SSH_USER}@${instance_ip}:./mirror-epel${VERSION_ID}.repo
#   $ssh_cmd $IMAGE_SSH_USER@$instance_ip "sudo cp mirror-epel${VERSION_ID}.repo /etc/yum.repos.d/"
# fi

# TODO: detect interface name
echo "INFO: do not set default gateway for second interface"
if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" ]]; then
  $ssh_cmd $IMAGE_SSH_USER@$instance_ip \
    "printf 'BOOTPROTO=dhcp\nDEVICE=eth1\nHWADDR=\$mac\nMTU=1500\nONBOOT=yes\nSTARTMODE=auto\nTYPE=Ethernet\nUSERCTL=no\nDEFROUTE=no\nPEERDNS=no\n' | sudo tee -a /etc/sysconfig/network-scripts/ifcfg-eth1 ; sudo systemctl restart NetworkManager.service"
fi

# enable ip_tables (used in UT for analytics)
$ssh_cmd $IMAGE_SSH_USER@$instance_ip "sudo modprobe ip_tables"

echo "INFO: check dns"
$ssh_cmd $IMAGE_SSH_USER@$instance_ip "time nslookup $(hostname)"
echo "INFO: cat /etc/resolv.conf"
$ssh_cmd $IMAGE_SSH_USER@$instance_ip "cat /etc/resolv.conf"
