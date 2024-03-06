#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

export ssh_private_key=$WORKER_SSH_KEY
export stackrc_file=${stackrc_file:-"stackrc.$JOB_NAME.env"}
stackrc_file_path=$WORKSPACE/$stackrc_file
# RHOSP_ID is a part of vm name - to be able to identify VM-s quickly
export RHOSP_ID=$BUILD_NUMBER
# pass versions from jenkins to devstack
export RHEL_VERSION=$ENVIRONMENT_OS
export RHOSP_VERSION

echo "# env file created by Jenkins" > "$stackrc_file_path"
echo "export DEPLOY_COMPACT_AIO=$DEPLOY_COMPACT_AIO" >> "$stackrc_file_path"
echo "export RHEL_POOL_ID=$RHEL_POOL_ID" >> "$stackrc_file_path"
echo "export ENABLE_RHEL_REGISTRATION=$ENABLE_RHEL_REGISTRATION" >> "$stackrc_file_path"
echo "export NAMESERVER_LIST=$NAMESERVER_LIST" >> "$stackrc_file_path"
echo "export NTP_SERVERS=$NTP_SERVERS" >> "$stackrc_file_path"
if [[ "$ENABLE_RHEL_REGISTRATION" == 'true' ]] ; then
  echo "export RHEL_USER=$RHEL_USER" >> "$stackrc_file_path"
  echo "export RHEL_PASSWORD=$RHEL_PASSWORD" >> "$stackrc_file_path"
fi
echo "export ENABLE_NETWORK_ISOLATION=$ENABLE_NETWORK_ISOLATION" >> "$stackrc_file_path"
echo "export OPENSTACK_CONTAINER_REGISTRY=$OPENSTACK_CONTAINER_REGISTRY" >> "$stackrc_file_path"
echo "export OPENSTACK_CONTAINER_TAG=$OPENSTACK_CONTAINER_TAG" >> "$stackrc_file_path"
if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then 
  echo "export ENABLE_TLS='ipa'" >> "$stackrc_file_path"
fi

if [[ -n "$JUMPHOST" ]]; then
  $my_dir/../../../infra/${JUMPHOST}/create_workers.sh
  source $stackrc_file_path

  if [[ "$PROVIDER" == 'bmc' ]]; then
    $WORKSPACE/src/opensdn-io/tf-devstack/rhosp/create_env.sh
  elif [[ "$PROVIDER" == 'kvm' ]]; then
    # devstack requires to run scripts on KVM host
    # TODO: make it symmetric with openstack/bmc - rework devstack scripts
    script="create_env.sh"
    cat <<EOF > $WORKSPACE/$script
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export ORCHESTRATOR=$ORCHESTRATOR
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export HUGEPAGES_ENABLED=$HUGEPAGES_ENABLED
export SSL_ENABLE=$SSL_ENABLE
export stackrc_file=$stackrc_file
source \$WORKSPACE/\$stackrc_file
export SSH_USER=stack
EOF
    for n in ${NODES//,/ }; do
      var=$(echo $n | cut -d ':' -f1)
      val=$(echo $n | cut -d ':' -f2,3)
      echo "export $var=\"$val\"" >> $WORKSPACE/$script
    done
    cat <<EOF >> $WORKSPACE/$script
src/opensdn-io/tf-devstack/rhosp/cleanup.sh
src/opensdn-io/tf-devstack/rhosp/create_env.sh
EOF
    chmod a+x $WORKSPACE/$script
    ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
    rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/$script,$WORKSPACE/$stackrc_file} $IMAGE_SSH_USER@$instance_ip:./
    # run this via eval due to special symbols in ssh_cmd
    eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./$script
  else
    echo "ERROR: unsupported provider $PROVIDER"
    exit 1
  fi
else
  res=1
  cp $stackrc_file_path $stackrc_file_path.original
  for (( i=1; i<=$VM_BOOT_RETRIES ; ++i )) ; do
    cp $stackrc_file_path.original $stackrc_file_path
    source $my_dir/../../../infra/${SLAVE}/definitions
    source $my_dir/../../../infra/${SLAVE}/functions.sh
    IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
    echo "export PROVIDER=$PROVIDER" >> "$stackrc_file_path"
    echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file_path"

    # initial values for undercloud (v?-standard-4)
    required_instances=1
    required_cores=4
    if [ -z "$NODES" ] ; then
      # default aio (v?-standard-8)
      required_instances=$(( required_instances + 1 ))
      required_cores=$(( required_cores + 8 ))
    fi
    for nodes in ${NODES//,/ }; do
      if [[ "$(echo "$nodes" | tr -cd ':' | wc -m)" != 2 ]]; then
        echo "ERROR: inappropriate input \"$nodes\" in \"$NODES\""
        exit 1
      fi
      node_name=$(echo $nodes | cut -d ':' -f1)
      node_flavor=${VM_TYPES[$(echo $nodes | cut -d ':' -f2)]}
      node_count=$(echo $nodes | cut -d ':' -f3)
      echo "export $node_name=\"$node_flavor:$node_count\"" >> "$stackrc_file_path"
      for j in {1..5}; do
        if node_vcpu=$(openstack flavor show $node_flavor | awk '/vcpus/{print $4}') ; then
          break
        fi
        sleep 10
      done
      required_instances=$(( required_instances + node_count ))
      required_cores=$(( required_cores + node_count * node_vcpu ))
    done
    if [[ "${SSL_ENABLE,,}" == 'true' ]] ; then
      # ipa (v2-highcpu-4)
      required_instances=$(( required_instances + 1 ))
      required_cores=$(( required_cores + 4 ))
    fi
    wait_for_free_resources $required_instances $required_cores

    echo "export SSH_USER=$IMAGE_SSH_USER" >> "$stackrc_file_path"

    # to prepare rhosp-environment.sh
    source $stackrc_file_path
    # TODO: rename vexxrc to openrc
    export vexxrc="$stackrc_file_path"
    if $WORKSPACE/src/opensdn-io/tf-devstack/rhosp/create_env.sh ; then
      echo "INFO: Running up hooks"
      # hooks are impleneted for openstack only
      if [[ -e $my_dir/../../../infra/hooks/rhel/up.sh ]] ; then
        ${my_dir}/../../../infra/hooks/rhel/up.sh
      fi
      res=0
      break
    fi

    echo "ERROR: Instances creation is failed. Retry"
    $my_dir/remove_workers.sh || true
    sleep $VM_BOOT_DELAY
  done

  if [[ $res != '0' ]]; then
    echo "ERROR: Instances creation is failed at $VM_BOOT_RETRIES attempts."
    exit 1
  fi
fi
