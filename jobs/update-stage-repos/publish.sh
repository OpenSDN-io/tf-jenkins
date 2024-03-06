#!/bin/bash

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

if [ -z ${REPOS_TYPE} ]; then
  echo "ERROR: REPOS_TYPE is undefined or empty"
  exit 1
fi

dest="$REPOUPDATER_USER_NAME@tf-mirrors.$SLAVE_REGION.$CI_DOMAIN"
rsync -a -e "ssh -i $REPOUPDATER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $dest:./

cat <<EOF | ssh -i $REPOUPDATER_SSH_KEY $SSH_OPTIONS $dest
export SLAVE_REGION=$SLAVE_REGION
export CI_DOMAIN=$CI_DOMAIN
./src/opensdn-io/tf-jenkins/jobs/update-stage-repos/publish_stage.sh ${REPOS_TYPE}
EOF
