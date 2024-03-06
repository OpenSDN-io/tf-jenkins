#!/bin/bash -x

source ~/rhel_account

if [[ -z $1 ]]; then
   echo "./$0 REPOS_TYPE"
   exit 1
fi


if [[ -z ${RHEL_USER+x} ]]; then
    echo "There is no Red Hat Credentials. Please export variable RHEL_USER "
    exit 1
fi

if [[ -z ${RHEL_PASSWORD+x} ]]; then
    echo "There is no Red Hat Credentials. Please export variable RHEL_PASSWORD "
    exit 1
fi

SSH_USER=${SSH_USER:-root}
REPOS_TYPE=$1
if [[ "$REPOS_TYPE" == "rhel7" ]]; then
    REDHAT_TAG='13.0'
    RHOSP_NAMESPACE="rhosp13"
elif [[ "$REPOS_TYPE" == "rhel82" ]]; then
    REDHAT_TAG='16.1'
    RHOSP_NAMESPACE="rhosp-rhel8"
elif [[ "$REPOS_TYPE" == "rhel84" ]]; then
    REDHAT_TAG='16.2'
    RHOSP_NAMESPACE="rhosp-rhel8"

fi

CEPH_NAMESPACE="rhceph"
REDHAT_REGISTRY="registry.redhat.io"
MIRROR_REGISTRY="mirrors:5005"

function wait_cmd_success() {
  # silent mode = don't print output of input cmd for each attempt.
  local cmd=$1
  local interval=${2:-3}
  local max=${3:-300}
  local silent_cmd=${4:-1}

  local state="$(set +o)"
  [[ "$-" =~ e ]] && state+="; set -e"

  set +o xtrace
  set -o pipefail
  local i=0
  if [[ "$silent_cmd" != "0" ]]; then
    local to_dev_null="&>/dev/null"
  else
    local to_dev_null=""
  fi
  while ! eval "$cmd" "$to_dev_null"; do
    printf "."
    i=$((i + 1))
    if (( i > max )) ; then
      echo ""
      echo "ERROR: wait failed in $((i*interval))s"
      eval "$cmd"
      eval "$state"
      return 1
    fi
    sleep $interval
  done
  echo ""
  echo "INFO: done in $((i*interval))s"
  eval "$state"
}


function wait_ssh() {
    local addr=$1
    local ssh_key=${2:-''}
    if [[ -n "$ssh_key" ]] ; then
        ssh_key=" -i $ssh_key"
    fi
    local interval=5
    local max=100
    local silent_cmd=1
    [[ "$DEBUG" != true ]] || silent_cmd=0
    if ! wait_cmd_success "ssh $ssh_opts $ssh_key ${SSH_USER}@${addr} uname -n" $interval $max $silent_cmd ; then
      echo "ERROR: Could not connect to VM $addr"
      exit 1
    fi
    echo "INFO: VM $addr is available"
}


dt=$(date +"%m-%d-%Y")
virt-clone --original sync_image_worker --name sync_image_worker-$dt --auto-clone

virsh start sync_image_worker-$dt
wait_ssh sync_image_worker

cd /tmp
rm run.sh
rm -rf tf-jenkins || true
git clone "https://gerrit.opensdn.io/r/opensdn-io/tf-jenkins"

cat <<EOF | tee -a run.sh
#!/bin/bash

export REPOS_TYPE=${REPOS_TYPE}
export MIRROR_REGISTRY=${MIRROR_REGISTRY}
export RHEL_USER=${RHEL_USER}
export RHEL_PASSWORD=${RHEL_PASSWORD}
export REDHAT_REGISTRY=${REDHAT_REGISTRY}
export CEPH_NAMESPACE=${CEPH_NAMESPACE}
export REDHAT_TAG=${REDHAT_TAG}
export RHOSP_NAMESPACE=${RHOSP_NAMESPACE}

./tf-jenkins/jobs/update-stage-images/update_docker_images.sh
./tf-jenkins/jobs/update-stage-images/publish_docker_images.sh
EOF

mirrors_host=$(grep mirrors /etc/hosts)
scp -r tf-jenkins run.sh root@sync_image_worker:
ssh root@sync_image_worker "echo $mirrors_host >>/etc/hosts"
ssh root@sync_image_worker chmod 755 ./run.sh
ssh root@sync_image_worker ./run.sh


virsh destroy sync_image_worker-$dt
virsh undefine --remove-all-storage sync_image_worker-$dt

