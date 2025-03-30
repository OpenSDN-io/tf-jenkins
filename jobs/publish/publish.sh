#!/bin/bash -e
set -o pipefail

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"


function log(){
  echo -e "INFO: $(date): $@"
}

function warn(){
  echo -e "WARNING: $(date): $@" >&2
}

function err(){
  echo -e "ERROR: $(date): $@" >&2
}

log "Publish TF container"

[ -z "$CONTAINER_REGISTRY" ] && { err "empty CONTAINER_REGISTRY" && exit -1; }
[ -z "$CONTAINER_TAG" ] && { err "empty CONTAINER_TAG" && exit -1; }
[ -z "$PUBLISH_TAGS" ] && { err "empty PUBLISH_TAGS" && exit -1; }

PUBLISH_REGISTRY=${PUBLISH_REGISTRY:-}
PUBLISH_REGISTRY_USER=${PUBLISH_REGISTRY_USER:-}
PUBLISH_REGISTRY_PASSWORD=${PUBLISH_REGISTRY_PASSWORD:-}
PUBLISH_INCLUDE_REGEXP=${PUBLISH_INCLUDE_REGEXP:-"contrail-\|tf-\|opensdn-"}
PUBLISH_EXCLUDE_REGEXP=${PUBLISH_EXCLUDE_REGEXP:-"base\|third-party-packages\|${DEVENV_IMAGE_NAME}"}
PUBLISH_CONTAINERS_LIST=${PUBLISH_CONTAINERS_LIST:-'auto'}

log_msg="\n CONTAINER_REGISTRY=$CONTAINER_REGISTRY"
log_msg+="\n PUBLISH_REGISTRY=${PUBLISH_REGISTRY}"
log_msg+="\n PUBLISH_REGISTRY_USER=${PUBLISH_REGISTRY_USER}"
log_msg+="\n PUBLISH_INCLUDE_REGEXP=${PUBLISH_INCLUDE_REGEXP}"
log_msg+="\n PUBLISH_EXCLUDE_REGEXP=${PUBLISH_EXCLUDE_REGEXP}"
log "Options:$log_msg"

if [[ -n "$PUBLISH_REGISTRY_USER" && "$PUBLISH_REGISTRY_PASSWORD" ]] ; then
  registry_addr=$(echo $PUBLISH_REGISTRY | cut -s -d '/' -f 1)
  log "Login to target docker registry $registry_addr"
  [[ $PUBLISH_REGISTRY =~ / ]] && registry_addr+=
  echo $PUBLISH_REGISTRY_PASSWORD | docker login --username $PUBLISH_REGISTRY_USER --password-stdin $registry_addr
fi

function run_with_retry() {
  local cmd=$@
  local attempt=0
  for attempt in {1..3} ; do
    if res="`eval $cmd`" ; then
      echo "$res"
      return 0
    fi
    sleep 1
  done
  return 1
}

container_registry_url="http://${CONTAINER_REGISTRY}"
log "Trying autodetect protocol for container registry"
log "Trying HTTP"
if curl -s -f --show-error ${container_registry_url}/v2/_catalog ; then
  raw_repos=$(run_with_retry timeout -s 9 10 curl -s -f --show-error ${container_registry_url}/v2/_catalog)
  log "Detected insecure docker registry ${CONTAINER_REGISTRY}"
  log "Setup insecure registry in /etc/docker/daemon.json"
  echo $(jq '. + {"insecure-registries" : ["'${CONTAINER_REGISTRY}'"]}' /etc/docker/daemon.json) > /etc/docker/daemon.json
  systemctl reload docker
else
  log "Trying HTTPS"
  container_registry_url="https://${CONTAINER_REGISTRY}"
fi

if [[ "${PUBLISH_CONTAINERS_LIST}" == 'auto' ]] ; then
  log "Request containers for publishing"
  if ! raw_repos=$(run_with_retry timeout -s 9 10 curl -s --show-error ${container_registry_url}/v2/_catalog) ; then
    err "Failed to request repo list from docker registry ${CONTAINER_REGISTRY}"
    exit -1
  fi

  repos=$(echo "$raw_repos" | jq -c -r '.repositories[]' | grep "$PUBLISH_INCLUDE_REGEXP" | grep -v "$PUBLISH_EXCLUDE_REGEXP")
else
  repos=$(echo $PUBLISH_CONTAINERS_LIST | tr ',' '\n')
fi

log "Repos for publishing:\n$repos"
if [[ -z "$repos" ]] ; then
  err "Nothing to publish:\nraw_repos=${raw_repos}\nrepos=$repos"
  exit -1
fi

function get_container_full_name_list() {
  local container=$1
  local lookup_tag=$2
  local registry=$(echo $container | cut -s -d '/' -f 1)
  local name=$(echo $container | cut -s -d '/' -f 2,3)
  local full_names=$container
  if [ -z "$name" ] ; then
    # just short name, loopup the tag
    local tags=$(run_with_retry timeout -s 9 10 curl -s --show-error ${container_registry_url}/v2/$container/tags/list | jq -c -r '.tags[]')
    if echo "$tags" | grep -q "^$lookup_tag\$" ; then
      full_names="${CONTAINER_REGISTRY}/${container}:${lookup_tag}"
    elif echo "$tags" | grep -q "^\(\(queens\)\|\(rocky\)\|\(stein\)\)-$lookup_tag\$" ; then
      full_names=$(echo "$tags" | awk "/^(queens|rocky|stein)-$lookup_tag\$/{print(\"${CONTAINER_REGISTRY}/${container}:\"\$0)}")
    else
      warn "No requested tag $lookup_tag in available tags for $container , available tags: "$tags
      return 1
    fi
  fi
  echo "$full_names"
}

function do_publish_impl() {
  local full_name=$1
  local target_tags=$2
  log "Pull $full_name"
  if ! run_with_retry docker pull $full_name ; then
    err "Failed to execute docker pull ${full_name}"
    return 1
  fi
  local t=''
  local ret=0
  for t in ${target_tags//,/ } ; do
    local target_tag="$PUBLISH_REGISTRY"
    [ -n "$target_tag" ] && target_tag+="/"
    target_tag+="${container}:${t}"
    log "Publish $target_tag started"
    if ! run_with_retry docker tag ${full_name} ${target_tag} ; then
      err "Failed to execute docker tag ${full_name} ${target_tag}"
      ret=1
      continue
    fi
    if ! run_with_retry docker push $target_tag ; then
      err "Failed to execute docker push $target_tag"
      ret=1
      continue
    fi
    log "Publish $full_name as $target_tag finished succesfully"
  done
  return $ret
}

function do_publish() {
  local container=$1

  local full_name_list=$(get_container_full_name_list $container $CONTAINER_TAG)
  if [[ "$?" != "0" || -z "$full_name_list" ]] ; then
    warn "$container skipped"
    return 0
  fi
  local ret=0
  local full_name=''
  for full_name in $full_name_list ; do
    local os=$(echo $full_name | awk -F ':' '{print($NF)}' | sed "s/\-$CONTAINER_TAG//g" | grep '\(queens\)\|\(rocky\)\|\(stein\)')
    if [ -n "$os" ] ; then
      local tags="${os}-${PUBLISH_TAGS//,/,${os}-}"
    else
      local tags=$PUBLISH_TAGS
    fi
    do_publish_impl $full_name $tags || ret=1
  done
  return $ret
}

jobs=""
for r in $repos ; do
  do_publish $r &
  jobs+=" $!"
done

was_errors=0
for j in $jobs ; do
  wait $j || {
    was_errors=1
  }
done

if [[ "$was_errors" != 0 ]] ; then
  err "Faield to publish TF containers"
  exit -1
fi

log "Publish TF container finished succesfully"
