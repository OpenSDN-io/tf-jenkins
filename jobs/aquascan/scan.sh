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

log "Scan TF containers"

[ -e $my_dir/scan.env ] && source $my_dir/scan.env

[ -z "$CONTAINER_REGISTRY" ] && { err "empty CONTAINER_REGISTRY" && exit -1; }
[ -z "$CONTAINER_TAG" ] && { err "empty CONTAINER_TAG" && exit -1; }
[ -z "${SCAN_REPORTS_STASH}" ] && { err "empty SCAN_REPORTS_STASH" && exit -1; }

AQUASEC_REGISTRY=registry.aquasec.com
SCAN_INCLUDE_REGEXP=${SCAN_INCLUDE_REGEXP:-"contrail-\|tf-\|opensdn-"}
SCAN_EXCLUDE_REGEXP=${SCAN_EXCLUDE_REGEXP:-"base\|third-party-packages\|${DEVENV_IMAGE_NAME}\|-src"}
SCAN_CONTAINERS_LIST=${SCAN_CONTAINERS_LIST:-'auto'}

log_msg="\n CONTAINER_REGISTRY=$CONTAINER_REGISTRY"
log_msg+="\n SCAN_INCLUDE_REGEXP=${SCAN_INCLUDE_REGEXP}"
log_msg+="\n SCAN_EXCLUDE_REGEXP=${SCAN_EXCLUDE_REGEXP}"
log "Options:$log_msg"

if [[ -n "$AQUASEC_REGISTRY" ]]; then
  log "Login to aquasec docker registry $AQUASEC_REGISTRY"
  if ! docker login "${AQUASEC_REGISTRY}" -u "${AQUASEC_REGISTRY_USER}" -p "${AQUASEC_REGISTRY_PASSWORD}"; then
    err "Logon to aquasec docker registry has failed!"
    exit -1
  fi
fi

rm -rf "${SCAN_REPORTS_STASH}"
mkdir -p "${SCAN_REPORTS_STASH}"

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
  raw_repos=$(run_with_retry timeout -s 9 10 curl -s --show-error ${container_registry_url}/v2/_catalog)
  log "Detected insecure docker registry ${CONTAINER_REGISTRY}"
  log "Setup insecure registry in /etc/docker/daemon.json"
  echo $(jq '. + {"insecure-registries" : ["'${CONTAINER_REGISTRY}'"]}' /etc/docker/daemon.json) > /etc/docker/daemon.json
  systemctl reload docker
else
  log "Trying HTTPS"
  container_registry_url="https://${CONTAINER_REGISTRY}"
fi

if [[ "${SCAN_CONTAINERS_LIST}" == 'auto' ]] ; then
  log "Query containers to scan"
  if ! raw_repos=$(run_with_retry timeout -s 9 10 curl -s --show-error ${container_registry_url}/v2/_catalog) ; then
    err "Failed to request repo list from docker registry ${CONTAINER_REGISTRY}"
    exit -1
  fi

  repos=$(echo "$raw_repos" | jq -c -r '.repositories[]' | grep "$SCAN_INCLUDE_REGEXP" | grep -v "$SCAN_EXCLUDE_REGEXP")
else
  repos=$(echo $SCAN_CONTAINERS_LIST | tr ',' '\n')
fi

if [[ -z "$repos" ]] ; then
  err "Nothing to scan:\nraw_repos=${raw_repos}\nrepos=$repos"
  exit -1
fi

function pull_eligible_image_names() {
	local r=$1
	run_with_retry timeout -s 9 10 curl -s -k ${container_registry_url}/v2/$r/tags/list | jq -c -r "select(.tags[] | inside(\"${CONTAINER_TAG}\")) | .name" | sort | uniq
}

function parse_scan_results() {
  local n=$1
  local j=${SCAN_REPORTS_STASH}/${n}.json
  if [[ -e $j ]]; then
    cat $j | jq -c -r "[..|objects|select(.nvd_score? or .vendor_score?) | .nvd_score, .vendor_score] | max"
  else
    echo null
  fi
}

function do_scan() {
	local r=$1
	local a=$AQUASEC_HOST

	for n in $(pull_eligible_image_names $r); do
		local i="${CONTAINER_REGISTRY}/$n:${CONTAINER_TAG}"
    log "Process image ${i}"
		if ! docker pull $i >/dev/null ; then
      log "Image ${i} is unavailable."
      continue
    fi
    local o=$(docker run --privileged --rm -v /var/run/docker.sock:/var/run/docker.sock -v ${SCAN_REPORTS_STASH}:/reports \
      ${AQUASEC_REGISTRY}/scanner:${AQUASEC_VERSION} \
      scan \
      -H http://${a}:8080 \
      -U "${SCANNER_USER}" \
      -P "${SCANNER_PASSWORD}" \
      --htmlfile /reports/${n}.html \
      --jsonfile /reports/${n}.json \
      --local "${i}" 2>/dev/null)
    local m=$(parse_scan_results $n)
    docker image rm $i >/dev/null
    if [[ -z "$m" || "$m" == null ]]; then
      log "Image ${n} does not have a score assessed by Aqua Scan. This image will be skipped."
      continue
    fi
    log "Image ${i} score: $m"
    if [[ "$SCAN_THRESHOLD" < "$m" ]]; then
      log "Image ${n} has at least one critical vulnerability. Max score was: ${m}"
      return 1
    fi
	done

  return 0
}

function do_scan_portion() {
  for x in $*; do
    do_scan $x || return $?
  done
}

jobs=""
repo_list=($repos)
repo_count=${#repo_list[*]}
parallelism_factor=10
if ((repo_count > parallelism_factor)); then
  portion_size=$(((repo_count + parallelism_factor - 1) / parallelism_factor))
  for((i = 0; i < $repo_count;)); do
    portion=()
    for((j=0; j < portion_size && i < repo_count; ++j, ++i)); do
      portion+=("${repo_list[$i]}")
    done
    do_scan_portion "${portion[*]}" &
    jobs+=" $!"
  done
else
  for r in $repos ; do
    do_scan $r &
    jobs+=" $!"
  done
fi

was_errors=0
for j in $jobs ; do
  wait $j || {
    was_errors=1
  }
done

if (( 0 != was_errors )); then
  err "Failed to scan TF containers"
  exit -1
fi

log "Scanning TF containers has finished succesfully"
