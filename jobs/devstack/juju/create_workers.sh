#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions${JUMPHOST:+.$JUMPHOST}"

if [[ -z "$JUMPHOST" ]] ; then
  # openstack/aws branch
  "$my_dir/../common/create_workers.sh"
  exit
fi

# here we have just one option - JUMPHOST=openlab2
# it's a bmc setup with MAAS

if [[ "$SLAVE" != 'openstack' ]]; then
  echo "ERROR: currently maas setup is accessible only from openstack slave"
  exit 1
fi

"$my_dir/../../../infra/$JUMPHOST/create_workers.sh"

ENV_FILE="$WORKSPACE/stackrc.$JOB_NAME.env"
source "$ENV_FILE"
ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./
cat <<EOF >> $WORKSPACE/run_prepare_maas.sh
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export MAAS_PROFILE="$MAAS_PROFILE"
export MAAS_API_KEY="$MAAS_API_KEY"
export MAAS_ENDPOINT="$MAAS_ENDPOINT"
export VIRTUAL_IPS="$VIRTUAL_IPS"
src/opensdn-io/tf-jenkins/infra/$JUMPHOST/prepare_maas.sh \$HOME/maas.vars
EOF
chmod a+x $WORKSPACE/run_prepare_maas.sh

rsync -a -e "$ssh_cmd" $WORKSPACE/run_prepare_maas.sh $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./run_prepare_maas.sh
