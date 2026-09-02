
function get_instance_ip() {
  local instance_id=$1
  local net=${2:-"$OS_NETWORK"}

  local networks
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    if networks=$(openstack server show $instance_id -c addresses -f value 2>&1) ; then
      break
    fi
    networks=""
    sleep 10
  done
  if [[ -z "$networks" ]]; then
    return
  fi
  for network in $networks; do
    if [[ " $network" =~ " $net=" ]]; then
      echo $network | cut -d "=" -f 2 | cut -d ";" -f 1 | cut -d "," -f 1
      break
    fi
  done
}

# caller must check for empty result
function get_network_cidr() {
  local net=$1
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    local res
    if res=$(openstack subnet list --network $net -c Subnet -f value 2>&1) ; then
      echo "$res | head -1"
      return
    fi
    sleep 10
  done
}

# caller must check for empty result
function get_network_gateway() {
  local net=$1
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    local res
    if res=$(openstack subnet list --network data -c ID -f value 2>&1) ; then
      subnet=$(echo "$res" | head -1)
      if [ -n "$subnet" ] && res=$(openstack subnet show $subnet -c gateway_ip -f value 2>/dev/null) ; then
        echo "$res"
        return
      fi
    fi
    sleep 10
  done
}

function list_instances() {
  local tags=$1
  local not_tags=${2:-}
  local opts="--tags ${tags}"
  if [[ -n "$not_tags" ]] ; then
    opts+=" --not-tags $not_tags"
  fi
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    local res
    if res=$(nova list $opts --minimal 2>/dev/null) ; then
      echo "$res" | awk '{print $2}' | grep -v ID | grep -v "^$" | tr '\n' ' '
      return
    fi
    sleep 10
  done
  echo "ERROR: can't list instances with tags=$tags and not_tags=$not_tags"
  echo "$res"
  return 1
}

function get_tag_value() {
  local instance=$1
  local tag=$2
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    local res
    if res=$(nova server-tag-list $instance 2>&1) ; then
      local kv=$(echo "$res" | awk '{print $2}' | grep -v "^Tag$" | grep "${tag}=")
      if [[ -n "$kv" ]] ; then
        echo $kv | cut -d '=' -f 2
      fi
    fi
    sleep 10
  done
  echo "ERROR: tag value (key=$tag) couldn't be obtained for instance $instance"
  echo "$res"
  return 1
}

function tier_down() {
  local instance=$1
  local down=$(get_tag_value $instance DOWN)
  if [[ -n "$down" && -e ${my_dir}/../hooks/${down}/down.sh ]] ; then
    local instance_ip=$(get_instance_ip $instance)
    if [[ -z "$instance_ip" ]]; then
      return 1
    fi
    ${my_dir}/../hooks/${down}/down.sh $instance_ip
  fi
}

function down_instances() {
  echo "INFO: do down nodes"
  local jobs=''
  local i=''
  for i in $@ ; do
    tier_down $i &
    jobs+=" $!"
  done
  for i in $jobs ; do
    wait $i || true
  done
}

function get_volume_list() {
  local volumes=""
  local i=''
  for i in $@ ; do
    volumes+=" $(openstack server show $i |  grep volumes_attached | awk -F[\'\'] '{print $2}')"
  done
  echo $volumes
}

function get_available_volume_id() {
  local volume_name=$1
  local list
  list=$(openstack volume list --name "$volume_name" -c ID -c Status -f value 2>/dev/null) || return 0
  echo "$list" | awk '$2=="available"{print $1}'
  return 0
}

function wait_for_volume_ready() {
  local volume_id=$1
  local i
  local status
  for (( i=0; i<30; i++ )) ; do
    status=$(openstack volume show "$volume_id" -c status -f value 2>/dev/null || true)
    if [[ "$status" == "available" ]]; then
      echo "Volume $volume_id is available"
      return 0
    elif [[ "$status" == "error" ]]; then
      echo "Volume $volume_id is in error state, would be deleted"
      openstack volume show "$volume_id" || true
      openstack volume delete "$volume_id" || true
      return 1
    fi
    sleep 10
  done
  echo "Waiting for availability of volume $volume_id too long, would be deleted"
  openstack volume show "$volume_id" || true
  openstack volume delete "$volume_id" || true
  return 1
}

function wait_for_free_resources() {
  local required_instances=$1
  local required_cores=$2
  local project_id
  local i
  for (( i=1; i<=5 ; ++i )) ; do
    # MCS cli doesn't support authorization by os_project_name, only by id
    # so we don't specify os_project_name on startup at all
    if project_id=$(openstack project show $OS_PROJECT_ID | awk '/ id /{print $4}') ; then
      break
    fi
    sleep 10
  done
  if [[ -z "$project_id" ]]; then
    echo "ERROR: Can't get project_id by name $OS_PROJECT_ID"
    return 1
  fi
  echo "INFO: project_id=$project_id"

  echo "INFO: wait for enough resources for required_instances=$required_instances and required_cores=$required_cores  $(date)"
  while true ; do
    local quotas
    local token=$(openstack token issue -c id -f value)
    local nova_endpoint=$(openstack catalog show nova -f value -c endpoints | python3 -c "import ast;print([e['url'] for e in ast.literal_eval(input()) if e['interface']=='public'][0])")
    if ! quotas=$(curl -s $nova_endpoint/limits -X GET -H "X-Auth-Token: $token" -H "Content-Type: application/json") ; then
        sleep $VM_BOOT_DELAY
        continue
    fi
    local instances_used=$(echo "$quotas" | jq .limits.absolute.totalInstancesUsed)
    local instances_limit=$(echo "$quotas" | jq .limits.absolute.maxTotalInstances)
    local cores_used=$(echo "$quotas" | jq .limits.absolute.totalCoresUsed)
    local cores_limit=$(echo "$quotas" | jq .limits.absolute.maxTotalCores)
    if (( instances_used + required_instances + RESERVED_INSTANCES_COUNT < instances_limit )) &&
        (( cores_used + required_cores + RESERVED_CORES_COUNT < cores_limit )) ; then
      break
    fi
    echo "INFO: waiting for free resources...  $(date)"
    echo "INFO: instances used=$instances_used  required=$NODES_COUNT  reserved=$RESERVED_INSTANCES_COUNT  limit=$instances_limit"
    echo "INFO: cores used=$cores_used  required=$required_cores  reserved=$RESERVED_CORES_COUNT  limit=$cores_limit"
    sleep $VM_BOOT_DELAY
  done
  echo "INFO: waiting for resources is finished  $(date)"
}
