#!/bin/bash -eE
set -o pipefail

# to cleanup all workers created by current pipeline

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"


# TODO: check if it's locked and do not fail job

if TERMINATION_LIST=$(list_instances PipelineBuildTag=${PIPELINE_BUILD_TAG}) ; then
  if DOWN_LIST=$(list_instances PipelineBuildTag=${PIPELINE_BUILD_TAG} DOWN=) ; then
    down_instances $DOWN_LIST || true
  fi

  volumes=$(get_volume_list $TERMINATION_LIST)
  for instance in $TERMINATION_LIST ; do
    openstack server show $instance
  done

  echo "INFO: Instances to terminate: $TERMINATION_LIST"
  openstack server delete --wait $(echo "$TERMINATION_LIST")
  if [[ -n "$volumes" ]] ; then
    openstack volume delete $volumes
  fi
fi

# delete untagged instances elder than 1 hour
MAX_DURATION=3600
# collect all unlocked instances without tags with names ending on number
TERMINATION_LIST=$(nova list --field locked,name --not-tags-any "SLAVE=openstack" | grep 'False' |  grep -E '[0-9]\s+[|]$' | tr -d '|' | awk '{print $1}')
C_DATE=$(date +%s)
for i in $TERMINATION_LIST; do
  echo "INFO: Test untagged instance for duration: $i"
  L_DATE=$(date --date $(nova show $i | grep 'OS-SRV-USG:launched_at' | tr -d '|' | awk '{print $NF}') +%s)
  DURATION=$(($C_DATE - $L_DATE))
  if [[ "$DURATION" -ge "$MAX_DURATION" ]]; then
    EXCEED+="$i "
  fi
done
if [[ "${#EXCEED[*]}" == "0" ]]; then
  exit
fi
echo "INFO: Exceed list: ${#EXCEED[@]}"
openstack server delete $EXCEED
