#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
stackrc_file=${stackrc_file:-"deps.${JOB_NAME}.${JOB_RND}.env"}
source $WORKSPACE/$stackrc_file

if [[ "$PROVIDER" == "bmc" ]]; then
    exit
fi

$WORKSPACE/src/opensdn-io/tf-devstack/rhosp/providers/openstack/cleanup.sh
