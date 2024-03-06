#!/bin/bash -eE
set -o pipefail

deployer=$1
# can be empty which means default set of stages in tf-devstack
stage=$2

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: Deploy $deployer/$stage ($JOB_NAME)"

script="deploy_${stage:-all}.sh"
cat <<EOF > $WORKSPACE/$script
#!/bin/bash -e
[ "${DEBUG,,}" == "true" ] && set -x
export WORKSPACE=\$HOME
export DEBUG=$DEBUG
export PROVIDER=$PROVIDER
export ORCHESTRATOR=$ORCHESTRATOR
export OPENSTACK_VERSION=$OPENSTACK_VERSION
export CONTAINER_REGISTRY="$CONTAINER_REGISTRY"
export DEPLOYER_CONTAINER_REGISTRY="$DEPLOYER_CONTAINER_REGISTRY"
export CONTRAIL_CONTAINER_TAG="$CONTRAIL_CONTAINER_TAG$TAG_SUFFIX"
export CONTRAIL_DEPLOYER_CONTAINER_TAG="$CONTRAIL_DEPLOYER_CONTAINER_TAG$TAG_SUFFIX"
export CONTRAIL_DEPLOYER_BRANCH="$CONTRAIL_DEPLOYER_BRANCH"
export CONFIG_API_WORKER_COUNT=$CONFIG_API_WORKER_COUNT
export SSL_ENABLE=$SSL_ENABLE
export CONTROLLER_NODES="$CONTROLLER_NODES"
export AGENT_NODES="$AGENT_NODES"
export CONTROL_NODES="$CONTROL_NODES"
export DATA_NETWORK="$DATA_NETWORK"
export ENABLE_DPDK_SRIOV="$ENABLE_DPDK_SRIOV"
export ENABLE_NAGIOS=$ENABLE_NAGIOS
export LEGACY_ANALYTICS_ENABLE="$LEGACY_ANALYTICS_ENABLE"
export HUGEPAGES_ENABLED=$HUGEPAGES_ENABLED
export HUGE_PAGES_2MB=$HUGE_PAGES_2MB
export PATH=\$PATH:/usr/sbin
export CONTAINER_RUNTIME=$CONTAINER_RUNTIME
export IPA_NODES=$IPA_NODES
export K8S_CA=$K8S_CA
export DEPLOY_IPA_SERVER=$DEPLOY_IPA_SERVER
export IPA_PASSWORD=$IPA_PASSWORD
export ENABLE_RHEL_REGISTRATION=false
export K8S_RESOLV_CONFG_MODE=none
export CERT_SIGNER=$CERT_SIGNER
export DOMAIN=$DOMAIN
export NAMESERVER_LIST=$NAMESERVER_LIST
export NTP_SERVERS=$NTP_SERVERS

EOF

if declare -f -F add_deployrc &>/dev/null ; then
  add_deployrc $WORKSPACE/$script
fi

echo "src/opensdn-io/tf-devstack/${deployer}/run.sh $stage" >> $WORKSPACE/$script
chmod a+x $WORKSPACE/$script

ssh_cmd="ssh -i $WORKER_SSH_KEY $SSH_OPTIONS $SSH_EXTRA_OPTIONS"
rsync -a -e "$ssh_cmd" {$WORKSPACE/src,$WORKSPACE/$script} $IMAGE_SSH_USER@$instance_ip:./
# run this via eval due to special symbols in ssh_cmd
eval $ssh_cmd $IMAGE_SSH_USER@$instance_ip ./$script || res=1

echo "INFO: Deploy $stage finished"
exit $res
