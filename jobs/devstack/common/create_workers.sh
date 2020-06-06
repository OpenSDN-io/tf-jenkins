#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

NODES=${NODES:-"$VM_TYPE:1"}

controllers=`echo $NODES | cut -d',' -f1`
controller_node_type=`echo $controllers | cut -d':' -f1`
controller_node_count=`echo $controllers | cut -d':' -f2`
export VM_TYPE=$controller_node_type
export NODES_COUNT=$controller_node_count
export WORKER_NAME_PREFIX='cn'
if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
  echo "ERROR: Instances were not created. Exit"
  exit 1
fi

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
CONTROLLER_IDS=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2`
CONTROLLER_NODES=`cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2`
sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"

#support single node case and old behavior
instance_ip=`echo $CONTROLLER_NODES | cut -d',' -f1`

AGENT_IDS=""
AGENT_NODES=$CONTROLLER_NODES
if [[ $NODES =~ ',' ]] ; then
  agents=`echo $NODES | cut -d',' -f2`
  if [[ -n $agents ]] ; then
    agent_node_type=`echo $agents | cut -d':' -f1`
    agent_node_count=`echo $agents | cut -d':' -f2`
    export VM_TYPE=$agent_node_type
    export NODES_COUNT=$agent_node_count
    export WORKER_NAME_PREFIX='an'
    if ! "$my_dir/../../../infra/${SLAVE}/create_workers.sh" ; then
      echo "ERROR: Instances were not created. Exit"
      exit 1
    fi

    AGENT_IDS=`cat $ENV_FILE | grep INSTANCE_IDS | cut -d'=' -f2`
    AGENT_NODES=`cat $ENV_FILE | grep INSTANCE_IPS | cut -d'=' -f2`
    sed -i '/INSTANCE_IDS=/d' "$ENV_FILE"
    sed -i '/INSTANCE_IPS=/d' "$ENV_FILE"
  fi
fi

#pass ids and ips to devstack with comma delimeter
INSTANCE_IDS="$(echo ${CONTROLLER_IDS},${AGENT_IDS})"
CONTROLLER_NODES="$(echo ${CONTROLLER_NODES})"
AGENT_NODES="$(echo ${AGENT_NODES})"
sed -i '/instance_ip=/d' "$ENV_FILE"

echo "export INSTANCE_IDS=\"$INSTANCE_IDS\"" >> "$ENV_FILE"
echo "export instance_ip=$instance_ip" >> "$ENV_FILE"
echo "export CONTROLLER_NODES=\"$CONTROLLER_NODES\"" >> "$ENV_FILE"
echo "export AGENT_NODES=\"$AGENT_NODES\"" >> "$ENV_FILE"