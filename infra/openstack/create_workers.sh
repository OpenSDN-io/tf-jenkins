#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"

# parameters for workers
VM_TYPE=${VM_TYPE:-'medium'}
NODES_COUNT=${NODES_COUNT:-1}
AZ=${AVAILABILITY_ZONE:-${SLAVE_REGION^^}}

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
touch "$ENV_FILE"
echo "# env file created by Jenkins" > "$ENV_FILE"
echo "export PROVIDER=$PROVIDER" >> "$ENV_FILE"
echo "export ENVIRONMENT_OS=${ENVIRONMENT_OS}" >> "$ENV_FILE"
if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" ]]; then
  cidr=$(get_network_cidr $OS_DATA_NETWORK)
  if [[ -z "$cidr" ]]; then
    echo "ERROR: failed to get CIDR for subnet in network '$OS_DATA_NETWORK'"
    exit 1
  fi
  echo "export DATA_NETWORK=$cidr" >> "$ENV_FILE"
  gw=$(get_network_gateway $OS_DATA_NETWORK)
  if [[ -z "$gw" ]]; then
    echo "ERROR: failed to get Gateway for subnet in network '$OS_DATA_NETWORK'"
    exit 1
  fi
  echo "export VROUTER_GATEWAY=$gw" >> "$ENV_FILE"
fi

IMAGE_TEMPLATE_NAME="${OS_IMAGES["${ENVIRONMENT_OS^^}"]}"
for (( i=1; i<=5 ; ++i )) ; do
  if IMAGE_NAME=$(openstack image list --status active -c Name -f value | grep "${IMAGE_TEMPLATE_NAME}" | sort -nr | head -n 1) ; then
    if IMAGE=$(openstack image show -c id -f value "$IMAGE_NAME") ; then
      break
    fi
  fi
  sleep 15
done
if [[ -z "$IMAGE" ]]; then
  echo "ERROR: can't retrieve image details to boot VM"
  exit 1
fi
echo "export IMAGE=$IMAGE" >> "$ENV_FILE"

IMAGE_SSH_USER=${OS_IMAGE_USERS["${ENVIRONMENT_OS^^}"]}
echo "export IMAGE_SSH_USER=$IMAGE_SSH_USER" >> "$ENV_FILE"

INSTANCE_TYPE=${VM_TYPES[$VM_TYPE]}
if [[ -z "$INSTANCE_TYPE" ]]; then
  echo "ERROR: invalid VM_TYPE=$VM_TYPE (can't get from VM_TYPES)"
  exit 1
fi
VOLUME_SIZE=${VOLUME_SIZE[$VM_TYPE]}
if [[ -z "$VOLUME_SIZE" ]]; then
  echo "ERROR: invalid VM_TYPE=$VM_TYPE (can't get from VOLUME_SIZE)"
  exit 1
fi
echo "INFO: VM_TYPE=$VM_TYPE  INSTANCE_TYPE=$INSTANCE_TYPE  VOLUME_SIZE=$VOLUME_SIZE"


function cleanup () {
  local cleanup_tag=$1
  local termination_list="$(list_instances ${cleanup_tag})"
  local volumes=''
  if [[ -n "${termination_list}" ]] ; then
    echo "INFO: Instances to terminate: $termination_list"
    for instance_id in $termination_list ; do
      if nova show "$instance_id" | grep 'locked' | grep 'False'; then
        volumes+=" $(get_volume_list $instance_id)"
        down_instances $instance_id || true
        openstack server delete "$instance_id" --wait
      fi
    done
    if [[ -n "$volumes" ]] ; then
      openstack volume delete $volumes
    fi
  fi
}

function wait_for_instance_availability () {
  local instance_ip=$1
  local res=0
  timeout 300 bash -c "\
  while /bin/true ; do \
    ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip 'uname -a' && break ; \
    sleep 10 ; \
  done" || res=1
  if [[ $res != 0 ]] ; then
    echo "ERROR: VM  with ip $instance_ip is unreachable. Exit "
    return 1
  fi
}

function update_instance_network () {
  local instance_id=$1
  local instance_ip=$2
  if [[ "${USE_DATAPLANE_NETWORK,,}" == "true" ]]; then
    if ! openstack server add network $instance_id $OS_DATA_NETWORK ; then
      echo "ERROR: Can't add data network for vm $instance_id"
    fi
  fi
  export instance_ip
  local image_up_script=${OS_IMAGES_UP["${ENVIRONMENT_OS^^}"]}
  if [[ -n "$image_up_script" && -e ${my_dir}/../hooks/${image_up_script}/up.sh ]] ; then
    ${my_dir}/../hooks/${image_up_script}/up.sh
  fi
}

function update_vm_port() {
  local instance_id=$1
  local net_name=$2

  local i
  local port_id
  for (( i=1; i<=5 ; ++i )) ; do
    if port_id=$(openstack port list --server $instance_id --network $net_name -f value -c id) ; then
      break
    fi
    sleep 10
  done
  if [[ -z "$port_id" ]]; then
    echo "ERROR: can't get port_id for $instance_id/$net_name"
    exit 1
  fi
  echo "DEBUG: port_id=$port_id for $instance_id in $net_name"
  for (( i=1; i<=5 ; ++i )) ; do
    if openstack port set --no-security-group $port_id ; then
      sleep 2
      if openstack port set --disable-port-security $port_id ; then
        return
      fi
    fi
    sleep 10
  done
  echo "ERROR: can't set port config for port $port_id"
  exit 1
}

if [[ -n $WORKER_NAME_PREFIX ]] ; then
  PREFIX="${WORKER_NAME_PREFIX}_"
else
  PREFIX=''
fi
instance_name="${PREFIX}${BUILD_TAG}"
job_tag="JobTag=${BUILD_TAG}"
group_tag="GroupTag=${PREFIX}${BUILD_TAG}"

for (( i=1; i<=5 ; ++i )) ; do
  if instance_vcpu=$(openstack flavor show $INSTANCE_TYPE | awk '/vcpus/{print $4}') ; then
    break
  fi
  sleep 10
done
if [[ -z "$instance_vcpu" ]]; then
  echo "ERROR: can't retrieve flavor details to boot VM"
  exit 1
fi
required_cores=$(( instance_vcpu * $NODES_COUNT ))

for (( i=1; i<=$VM_BOOT_RETRIES ; ++i )) ; do
  ready_nodes=0
  INSTANCE_IDS=""
  INSTANCE_IPS=""
  DATA_NET_IPS=""

  wait_for_free_resources $NODES_COUNT $required_cores

  res=0

  for i in $(seq 1 $NODES_COUNT) ; do
    # Volumes creation
    VOLUME_RETRIES=${VOLUME_RETRIES:-5}
    for (( k=1; k<=${VOLUME_RETRIES} ; ++k )) ; do
      instance_name_num=${instance_name}_${i}
      echo "INFO: openstack volume create --type $VOLUME_TYPE --size $VOLUME_SIZE \
        --availability-zone $AZ --image $IMAGE --bootable ${instance_name_num}_volume"
      openstack volume create \
        --type "${VOLUME_TYPE}" \
        --size "${VOLUME_SIZE}" \
        --availability-zone "${AZ}" \
        --image "${IMAGE}" \
        --bootable \
        ${instance_name_num}

      if wait_for_volume_ready ${instance_name_num} ; then
        break
      fi
      if [[ $k == ${VOLUME_RETRIES} ]] ; then
        echo "ERROR: Volume creation failed for ${VOLUME_RETRIES} times. Terminating"
        cleanup ${group_tag}
        exit 1
      else
        echo "ERROR: Volume creation failed. Retry..."
      fi
    done

    echo "INFO: openstack server create --volume ${instance_name_num} \
      --flavor ${INSTANCE_TYPE} --security-group ${OS_SG} --availability-zone ${AZ} \
      --key-name=worker --network ${OS_NETWORK} --wait ${instance_name_num}"
    openstack server create \
      --volume ${instance_name_num} \
      --flavor ${INSTANCE_TYPE} \
      --security-group ${OS_SG} \
      --availability-zone ${AZ} \
      --key-name=worker \
      --network ${OS_NETWORK} \
      --wait \
      ${instance_name_num} || res=1

    if [[ $res == 0 ]]; then
      nova server-tag-add ${instance_name_num} PipelineBuildTag=${PIPELINE_BUILD_TAG} \
                                       ${job_tag} ${group_tag} SLAVE=${SLAVE} \
                                       DOWN=${OS_IMAGES_DOWN["${ENVIRONMENT_OS^^}"]}
    fi
  done

  if [[ $res == 1 ]]; then
    echo "ERROR: Instances creation is failed on nova boot. Retry"
    cleanup ${group_tag}
    sleep $VM_BOOT_DELAY
    continue
  fi
  INSTANCE_IDS="$( list_instances ${group_tag} )"

  for instance_id in $INSTANCE_IDS ; do
    instance_ip=$(get_instance_ip $instance_id)
    if [[ -z "$instance_ip" ]]; then
      echo "ERROR: Can't get instance's IP by its id=$instance_id. Clean up"
      cleanup ${group_tag}
      break
    fi
    if ! wait_for_instance_availability $instance_ip ; then
      echo "ERROR: Node with $instance_ip is not available. Clean up"
      cleanup ${group_tag}
      break
    fi
    if ! update_instance_network $instance_id $instance_ip ; then
      echo "ERROR: Can't update network for $instance_id. Clean up"
      cleanup ${group_tag}
      break
    fi

    ready_nodes=$(( ready_nodes + 1 ))
    INSTANCE_IPS+="$instance_ip,"

    update_vm_port $instance_id $OS_NETWORK

    if [[ ${USE_DATAPLANE_NETWORK,,} == "true" ]]; then
      DATA_NET_IPS+="$(get_instance_ip $instance_id $OS_DATA_NETWORK),"
      update_vm_port $instance_id $OS_DATA_NETWORK
    fi
  done

  if (( ready_nodes == NODES_COUNT )) ; then
    if [[ -n "$INSTANCE_IPS" ]] ; then
      INSTANCE_IDS="$(echo "$INSTANCE_IDS" | sed 's/ /,/g')"
      echo "export INSTANCE_IDS=$INSTANCE_IDS" >> "$ENV_FILE"
      echo "export INSTANCE_IPS=$INSTANCE_IPS" >> "$ENV_FILE"
      if [[ -n $DATA_NET_IPS ]]; then
        echo "export DATA_NET_IPS=$DATA_NET_IPS" >> "$ENV_FILE"
      fi
      instance_ip=`echo $INSTANCE_IPS | cut -d',' -f1`
      echo "export instance_ip=$instance_ip" >> "$ENV_FILE"
    fi
    exit 0
  fi
done

echo "INFO: Nodes are not created."
touch "$ENV_FILE"
exit 1
