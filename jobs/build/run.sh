#!/bin/bash -eE
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

my_file="$(readlink -e "$0")"
my_dir="$(dirname $my_file)"

if [[ -n "$JUMPHOST" ]]; then
    source "$my_dir/../../infra/${JUMPHOST}/definitions"
else
    source "$my_dir/definitions"
fi

if [[ "$STAGE" == 'freeze' ]] && [[ "$GERRIT_PIPELINE" != 'gate' || "$GERRIT_BRANCH" != 'master' ]]; then
  echo "INFO: Freeze works only for gate pipeline and for master branch"
  exit
fi
if [[ "$DEVENV_TAG" == 'frozen' ]] && [[ "$STAGE" == 'none' ]] && [[ ("$GERRIT_PIPELINE" != 'check' && "$GERRIT_PIPELINE" != 'templates') || "$GERRIT_BRANCH" != 'master' ]]; then
  # use frozen only for check pipeline
  unset DEVENV_TAG
fi

# transfer patchsets info into sandbox
if [ -e $WORKSPACE/patchsets-info.json ]; then
  mkdir -p $WORKSPACE/src/opensdn-io/tf-dev-env/input/
  cp -f $WORKSPACE/patchsets-info.json $WORKSPACE/src/opensdn-io/tf-dev-env/input/
fi

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS"

echo "INFO: Build started: ENVIRONMENT_OS=$ENVIRONMENT_OS LINUX_DISTR=$LINUX_DISTR"

export DEVENV_TAG=${DEVENV_TAG:-stable${TAG_SUFFIX}}
export BUILD_MODE="fast"
if grep -q "opensdn-io/tf-dev-env" ./patchsets-info.json ; then
  # changes in tf-dev-env - we have to rebuild it
  export DEVENV_TAG="sandbox-$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
fi

# list for tf containers
mirror_list=""
# list of repos for building of tf-dev-sandbox container itself
mirror_list_for_build=""

if [[ ${LINUX_DISTR} == 'rhel7' ]]; then
  mirror_list_for_build="mirror-epel7.repo rhel84/mirror-rhel84-baseos.repo"
  mirror_list=""
elif [[ ${LINUX_DISTR} == 'centos' ]]; then
  mirror_list_for_build="mirror-epel7.repo mirror-docker.repo mirror-base-centos7.repo"
  # epel must not be there - it cause incorrect installs and fails at runtime
  # + rocky9 repo for build-init image
  mirror_list="mirror-base-centos7.repo mirror-openstack.repo mirror-docker.repo"
  mirror_list+=" rocky9/rocky.repo rocky9/rocky-extras.repo rocky9/rocky-devel.repo rocky9/rocky-addons.repo mirror-base-rocky9.repo"
  # add empty CentOS repos to disable them
  mirror_list_for_build+=" centos7/CentOS-Base.repo centos7/CentOS-CR.repo centos7/CentOS-Debuginfo.repo centos7/CentOS-Media.repo"
  mirror_list_for_build+=" centos7/CentOS-Sources.repo centos7/CentOS-Vault.repo centos7/CentOS-fasttrack.repo centos7/CentOS-x86_64-kernel.repo"
  mirror_list+=" centos7/CentOS-Base.repo centos7/CentOS-CR.repo centos7/CentOS-Debuginfo.repo centos7/CentOS-Media.repo"
  mirror_list+=" centos7/CentOS-Sources.repo centos7/CentOS-Vault.repo centos7/CentOS-fasttrack.repo centos7/CentOS-x86_64-kernel.repo"
elif [[ "${LINUX_DISTR}" =~ 'ubi7' ]] ; then
  mirror_list_for_build="mirror-epel7.repo rhel7/ubi.repo rhel7/mirror-rhel7.repo rhel84/mirror-rhel84-baseos.repo"
  mirror_list="rhel7/ubi.repo rhel7/mirror-rhel7.repo"
elif [[ "${LINUX_DISTR}" =~ 'ubi8' ]] ; then
  mirror_list_for_build="mirror-epel8.repo rhel84/ubi.repo rhel84/mirror-rhel84.repo"
  mirror_list="rhel84/ubi.repo rhel84/mirror-rhel84.repo"
elif [[ ${LINUX_DISTR} == 'rockylinux' ]]; then
  mirror_list_for_build="mirror-epel9.repo mirror-docker9.repo mirror-base-rocky9.repo"
  mirror_list="mirror-epel9.repo mirror-base-rocky9.repo mirror-docker9.repo"
  # # add empty Rocky repos to disable them
  mirror_list_for_build+=" rocky9/rocky.repo rocky9/rocky-extras.repo rocky9/rocky-devel.repo rocky9/rocky-addons.repo"
  mirror_list+=" rocky9/rocky.repo rocky9/rocky-extras.repo rocky9/rocky-devel.repo rocky9/rocky-addons.repo"
fi

if [[ "$GERRIT_BRANCH" != 'master' ]]; then
  # add more branches to condition after release
  export UBUNTU_CODENAME='jammy'
else
  export UBUNTU_CODENAME='noble'
fi
# include mirror-base* always for later usage 
for repofile in $mirror_list_for_build $mirror_list mirror-base-centos7.repo mirror-base-rocky9.repo mirror-docker.repo mirror-pip.conf mirror-docker-daemon.json ubuntu-sources.list ; do
  file="${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/${repofile}"
  cat $file | envsubst > $file.tmp
  mv $file.tmp $file
done

res=0
script="build-$STAGE-$TARGET.sh"
cat <<EOF > $WORKSPACE/$script
[ "${DEBUG,,}" == "true" ] && set -x
export DEBUG=$DEBUG
export PATH=\$PATH:/usr/sbin

export WORKSPACE=\$HOME
# dont setup own registry
export CONTRAIL_DEPLOY_REGISTRY=0
# to not to bind contrail sources to container
export CONTRAIL_DIR=""

export LINUX_DISTR=$LINUX_DISTR
export LINUX_DISTR_VER=${LINUX_DISTR_VER}
export SITE_MIRROR=$SITE_MIRROR
export GERRIT_URL=${GERRIT_URL}
export GERRIT_BRANCH=${GERRIT_BRANCH}
export GERRIT_PROJECT=${GERRIT_PROJECT}

# devenvtag is passed from parent job
export DEVENV_TAG=$DEVENV_TAG
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
export CONTRAIL_CONTAINER_TAG=$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX
export CONTRAIL_KEEP_LOG_FILES=true
export INSECURE_REGISTRIES=${INSECURE_REGISTRIES}
export MULTI_KERNEL_BUILD=true
export KERNEL_REPOSITORIES_RHEL8="--disablerepo=* --enablerepo=BaseOS"
export BUILD_MODE=$BUILD_MODE
export DEBUGINFO=$DEBUGINFO

export CONTRAIL_PARALLEL_BUILD=$CONTRAIL_PARALLEL_BUILD

cd src/opensdn-io/tf-dev-env

# TODO: use in future generic mirror approach
# Copy yum repos for rhel from host to containers to use local mirrors

rm -rf ./config/etc
mkdir -p ./config/etc/yum.repos.d
case "${ENVIRONMENT_OS,,}" in
  rhel7* )
    # TODO: now no way to put gpg keys into containers for repo mirrors
    # disable gpgcheck as keys are not available inside the contianers
    for frepo in \$(find /etc/yum.repos.d/ -name "*.repo" -printf "%P\\n") ; do
      cp -f /etc/yum.repos.d/\$frepo ./config/etc/yum.repos.d/
      sed -i 's/^gpgcheck.*/gpgcheck=0/g' ./config/etc/yum.repos.d/\$frepo
      cp -f ./config/etc/yum.repos.d/\$frepo ./container/\$frepo
    done
    ;;
  centos* )
    # copy docker and base repos to local machine
    sudo cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
    sudo cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-base-centos7.repo /etc/yum.repos.d/
    ;;
  rocky9* )
    # copy docker and base repos to local machine
    sudo cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-docker.repo /etc/yum.repos.d/
    sudo cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-base-rocky9.repo /etc/yum.repos.d/
    ;;
esac
for mirror in $mirror_list_for_build ; do
  cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/\$mirror ./container/
done
for mirror in $mirror_list ; do
  cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/\$mirror ./config/etc/yum.repos.d/
done

mkdir -p ./config/etc/apt
cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/ubuntu-sources.list ./config/etc/apt/sources.list

cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-pip.conf ./config/etc/pip.conf
cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-pip.conf ./container/pip.conf

sudo mkdir -p /etc/docker/
sudo cp \${WORKSPACE}/src/opensdn-io/tf-jenkins/infra/mirrors/mirror-docker-daemon.json /etc/docker/daemon.json

echo "INFO: df -h"
df -h
echo "INFO: free -h"
free -h

./run.sh "$STAGE" "$TARGET"
EOF
chmod a+x $WORKSPACE/$script

# sync should be made after optional repo URLs updating
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/$script} $IMAGE_SSH_USER@$instance_ip:./

# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./$script || res=1

if [[ "$res" != '0' ]] ; then
  echo "ERROR: Run failed. Stage: $STAGE  Target: $TARGET"
  exit $res
fi

rm -rf build.env
touch build.env
if [[ "$STAGE" == "fetch" ]]; then
  # after fetching sources we have to copy this file to publish it for UT
  rsync -a -e "$ssh_cmd" $IMAGE_SSH_USER@$instance_ip:output/unittest_targets.lst $WORKSPACE/unittest_targets.lst || res=1
  echo "export UNITTEST_TARGETS=$(cat $WORKSPACE/unittest_targets.lst | tr '\n' ',')" >> build.env
fi

# hack to not re-push just pulled tf-dev-sandbox:stable
if [[ "$PUBLISH_TYPE" == 'stable' ]]; then
  if ! $ssh_cmd $IMAGE_SSH_USER@$instance_ip "find output/logs" | grep -q "build-tf-dev-env.log" ; then
    echo "INFO: build log of tf-dev-sandbox:stable is not found - skipping publishing"
    PUBLISH_TYPE=""
  fi
fi

if [[ -n "$PUBLISH_TYPE" ]]; then
  if [[ "$PUBLISH_TYPE" == 'stable' ]]; then
    tag="$DEVENV_TAG"
  elif [[ "$PUBLISH_TYPE" == 'build' ]]; then
    tag="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
  elif [[ "$PUBLISH_TYPE" == 'frozen' ]]; then
    tag="frozen$TAG_SUFFIX"
  else
    echo "ERROR: unsupported publish type: $PUBLISH_TYPE"
    exit 1
  fi
  cat <<EOF | $ssh_cmd $IMAGE_SSH_USER@$instance_ip || res=1
set -eo pipefail
export WORKSPACE=\$HOME
export DEVENV_PUSH_TAG=$tag
export CONTAINER_REGISTRY=$CONTAINER_REGISTRY
src/opensdn-io/tf-dev-env/run.sh upload
EOF

  if [[ "$res" != '0' ]] ; then
    echo "ERROR: Publish failed for tag $tag. Stage: $STAGE  Target: $TARGET"
    exit $res
  fi

  # save DEVENV_TAG that was pushed by this job
  # chidlren jobs may have own TAG_SUFFIX and they shouldn't rely on it
  echo "export DEVENV_TAG=$tag" >> build.env
fi

echo "INFO: Build finished successfully"
