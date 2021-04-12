#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

source "$my_dir/definitions"

# transfer unittest targets info into sandbox
mkdir -p $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
if [ -e $WORKSPACE/unittest_targets.lst ]; then
  cp -f $WORKSPACE/unittest_targets.lst $WORKSPACE/src/tungstenfabric/tf-dev-env/input/
fi
# pass target_set as a additional key name for file names in log folder or as a tox target
echo $TARGET_SET > $WORKSPACE/src/tungstenfabric/tf-dev-env/input/target_set

STAGE=${STAGE:-test}

echo "INFO: UT started"

mirror_list=""
# list of repos for building of tf-dev-sandbox container itself
mirror_list_for_build=""
# substitute repos only for centos7
if [[ ${LINUX_DISTR} == 'centos' ]]; then
  mirror_list_for_build="mirror-epel.repo google-chrome.repo mirror-docker.repo mirror-base.repo "
  # epel must not be there - it cause incorrect installs and fails at runtime
  mirror_list="mirror-base.repo"
  # add empty CentOS repos to disable them
  mirror_list_for_build+=" centos7/CentOS-Base.repo centos7/CentOS-CR.repo centos7/CentOS-Debuginfo.repo centos7/CentOS-Media.repo"
  mirror_list_for_build+=" centos7/CentOS-Sources.repo centos7/CentOS-Vault.repo centos7/CentOS-fasttrack.repo centos7/CentOS-x86_64-kernel.repo"
  mirror_list+=" centos7/CentOS-Base.repo centos7/CentOS-CR.repo centos7/CentOS-Debuginfo.repo centos7/CentOS-Media.repo"
  mirror_list+=" centos7/CentOS-Sources.repo centos7/CentOS-Vault.repo centos7/CentOS-fasttrack.repo centos7/CentOS-x86_64-kernel.repo"
fi
for repofile in $mirror_list_for_build $mirror_list mirror-base.repo mirror-docker.repo mirror-pip.conf mirror-docker-daemon.json ; do
  file="${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/${repofile}"
  cat $file | envsubst > $file.tmp
  mv $file.tmp $file
done

# sync should be made after optional repo URLs updating
rsync -a -e "ssh -i $WORKER_SSH_KEY $SSH_OPTIONS" $WORKSPACE/src $IMAGE_SSH_USER@$instance_ip:./

function run_over_ssh() {
  res=0
cat <<EOF | ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $IMAGE_SSH_USER@$instance_ip || res=1
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0

export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export SITE_MIRROR=$SITE_MIRROR
export GERRIT_URL=${GERRIT_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}
export GERRIT_PROJECT=${GERRIT_PROJECT}

export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX

# to not to bind contrail sources to container
export CONTRAIL_DIR=""

# devenftag is passed from parent fetch-sources job
export DEVENV_TAG=$DEVENV_TAG
export DEVENV_PUSH_TAG=$DEVENV_TAG$DEVENV_PUSH_TAG

# Some tests (like test.test_flow.FlowQuerierTest.test_1_noarg_query) expect
# PST timezone, and fail otherwise.
timedatectl
sudo timedatectl set-timezone America/Los_Angeles
timedatectl

cd src/tungstenfabric/tf-dev-env

# TODO: unify this with build/run.sh
mkdir -p ./config/etc/yum.repos.d

for mirror in $mirror_list_for_build ; do
  cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/\$mirror ./container/
done
for mirror in $mirror_list ; do
  cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/\$mirror ./config/etc/yum.repos.d/
done

# substitute repos only for centos7
if [[ "${ENVIRONMENT_OS,,}" == 'centos7' ]]; then
  # copy base & docker repo to local machine
  sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-base.repo /etc/yum.repos.d/
  sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
fi

cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf

sudo mkdir -p /etc/docker/
sudo cp \${WORKSPACE}/src/tungstenfabric/tf-jenkins/infra/mirrors/mirror-docker-daemon.json /etc/docker/daemon.json

./run.sh $@
EOF
return $res
}

if ! run_over_ssh $STAGE $TARGET ; then
  echo "ERROR: UT failed"
  exit 1
fi

# DEVENV_PUSH_TAG is just a suffix here for final tag
# it was used for 'compile' job that is not present now
if [[ -n "$DEVENV_PUSH_TAG" ]]; then
  if ! run_over_ssh upload ; then
    echo "ERROR: push to registry with tag=$DEVENV_PUSH_TAG failed"
    exit 1
  fi
  # save DEVENV_TAG that is pushed by this job
  echo "export DEVENV_TAG=$DEVENV_TAG$DEVENV_PUSH_TAG" > testunit.env
fi

echo "INFO: UT finished successfully"
