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

# do ssh and cat for /etc/os-release - it's a symlink
ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "cat /etc/os-release" 2>/dev/null > $WORKSPACE/os-release
source $WORKSPACE/os-release
export UBUNTU_CODENAME

cat $my_dir/../../mirrors/mirror-pip.conf | envsubst > "$WORKSPACE/mirror-pip.conf"
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/mirror-pip.conf" ${IMAGE_SSH_USER}@${instance_ip}:./pip.conf
cat $my_dir/../../mirrors/mirror-docker-daemon.json | envsubst > "$WORKSPACE/mirror-docker-daemon.json"
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/mirror-docker-daemon.json" ${IMAGE_SSH_USER}@${instance_ip}:./docker-daemon.json
cat $my_dir/../../mirrors/ubuntu-sources.list | envsubst > "$WORKSPACE/ubuntu-sources.list"
rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/ubuntu-sources.list" ${IMAGE_SSH_USER}@${instance_ip}:./ubuntu-sources.list

# disable tx checksumming to avoid communication issues between workers
ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "interface=\$(ip route show | grep 'default via' | awk '{print \$5}');
if [ -n \"\$interface\" ]; then echo \"Found interface: \$interface\"; sudo ethtool -K \"\$interface\" tx off; else echo 'No physical interface found'; fi"

# we have to wait for cloud-init finish cause it may overwrite our copy of sources.list
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip
set -e
echo "INFO: wait for cloud-init finish"
while ps ax | grep -v grep | grep 'cloud-init' ; do
  sleep 1
done
sleep 2
echo "INFO: cloud-init finished"

if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" ]]; then
  echo "INFO: wait for second interface"
  ip l
  for ((i=0; i<120; i++)); do
    if [[ \$(ip l | grep -c 'link/ether') == '2' ]]; then
      break
    fi
    sleep 1
  done
  ip l
  if [[ \$(ip l | grep -c 'link/ether') != '2' ]]; then
    echo "ERROR: second inteface is absent. exiting..."
    exit 1
  fi
  echo "INFO: second interface found"
  ip l
fi

sudo cp -f ./pip.conf /etc/pip.conf
sudo mkdir -p /etc/docker/
sudo cp -f ./docker-daemon.json /etc/docker/daemon.json

echo "INFO: Update ubuntu OS"
sudo sudo cp -f ./ubuntu-sources.list /etc/apt/sources.list
echo "APT::Acquire::Retries \"10\";" | sudo tee /etc/apt/apt.conf.d/80-retries
sudo cp -f /usr/share/unattended-upgrades/20auto-upgrades-disabled /etc/apt/apt.conf.d/ || /bin/true

echo "INFO: disable ufw"
sudo ufw disable

if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" ]]; then
  # hack to reconfig netplan
  # https://askubuntu.com/questions/1104285/how-do-i-reload-network-configuration-with-cloud-init/1503265#1503265
  wget http://launchpadlibrarian.net/713462297/cloud-init_23.4.3-0ubuntu0~22.04.1_all.deb
  sudo apt-get install -y --allow-downgrades ./cloud-init_23.4.*.deb
  sudo cloud-init clean --configs network
  sudo cloud-init init --local

  echo "            dhcp4-overrides:" | sudo tee -a /etc/netplan/50-cloud-init.yaml
  echo "                use-routes: false" | sudo tee -a /etc/netplan/50-cloud-init.yaml
  echo "                use-dns: false" | sudo tee -a /etc/netplan/50-cloud-init.yaml
  sudo chmod 600 /etc/netplan/50-cloud-init.yaml
  sudo netplan apply
  sleep 1
fi
sudo cat /etc/netplan/50-cloud-init.yaml
ip a

echo "INFO: cat /etc/resolv.conf"
cat /etc/resolv.conf
echo "INFO: cat /run/systemd/resolve/resolv.conf"
cat /run/systemd/resolve/resolv.conf
echo "INFO: check dns"
time nslookup $(hostname)
EOF

if [ -f $my_dir/../../mirrors/ubuntu-environment ]; then
  echo "INFO: copy additional environment to host"
  cat $my_dir/../../mirrors/ubuntu-environment | envsubst > "$WORKSPACE/ubuntu-environment"
  rsync -a -e "ssh -i ${WORKER_SSH_KEY} ${SSH_OPTIONS}" "$WORKSPACE/ubuntu-environment" ${IMAGE_SSH_USER}@${instance_ip}:./ubuntu-environment
  ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip "cat ubuntu-environment | sudo tee -a /etc/environment"
fi
