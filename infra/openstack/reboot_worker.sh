#!/bin/bash -e

# to remove just job's workers

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"
source "$my_dir/functions.sh"
source "$WORKSPACE/global.env"

instance_ip=$1
instance_id=$(openstack server list | grep -E "${instance_ip}[^0-9]+" | awk '{print $2}')
echo "INFO: reboot server with IP=$instance_ip and id=$instance_id"
openstack server reboot --hard --wait $instance_id
