#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_dir="$(realpath $(dirname "$0"))"

source "$my_dir/definitions"

targets_file="$WORKSPACE/unittest_targets.lst"
rm -f "$targets_file"
touch "$targets_file"

# hardcoded sets of targets
agent=",controller/src/agent:test,controller/src/cat:test,"
bgp=",controller/src/bgp:test,controller/src/cat:test_upgrade,"
opserver=",src/contrail-analytics/contrail-opserver:test,"

group_one=",src/contrail-analytics/contrail-collector:test,"
group_one+="src/contrail-analytics/contrail-query-engine:test,"
group_one+="src/contrail-analytics/tf-topology:test,"
group_one+="contrail-nodemgr:test,vrouter-py-ut:test,"
group_one+="controller/src/config/svc_monitor:test,controller/src/config/schema-transformer:test,"
group_one+="controller/src/container/kube-manager:test,"

group_two=",controller/src/config/vnc_openstack:test,controller/src/config/api-server:test,"
group_two+="controller/src/config/utils:test,controller/src/config/device-manager:test,"

if [[ "$TARGET_SET" == "agent" ]]; then
  for target in $(echo $agent | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "bgp" ]]; then
  for target in $(echo $bgp | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "opserver" ]]; then
  for target in $(echo $opserver | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "group-one" ]]; then
  for target in $(echo $group_one | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "group-two" ]]; then
  for target in $(echo $group_two | tr ',' ' ') ; do
    if echo ",$UNITTEST_TARGETS," | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
elif [[ "$TARGET_SET" == "ungrouped" ]]; then
  excludes="${agent}${bgp}${opserver}${group_one}${group_two}"
  for target in $(echo "$UNITTEST_TARGETS" | tr ',' ' ') ; do
    if [[ ! "$target" =~ ^src/contrail-analytics/.*$ ]] && ! echo "$excludes" | grep -q ",$target," ; then
      echo "$target" >> "$targets_file"
    fi
  done
else
  echo "ERROR: unknown target $TARGET_SET"
  exit 1
fi

if [[ "$(cat $WORKSPACE/unittest_targets.lst | wc -l | xargs)" == '0' ]]; then
  echo "INFO: filtered set is empty"
  exit 1
fi

echo "INFO: filtered set:"
cat $WORKSPACE/unittest_targets.lst
