#!/bin/bash -e

current_tag=$1
new_tag=$2

if [[ -z "current_tag" || -z "new_tag" ]]; then
  echo "ERROR: please specify tag: docker_tag.sh latest release-1"
  exit 1
fi

docker login

images="\
contrail-analytics-alarm-gen \
contrail-analytics-api \
contrail-analytics-collector \
contrail-analytics-query-engine \
contrail-analytics-snmp-collector \
contrail-analytics-snmp-topology \
contrail-controller-config-api \
contrail-controller-config-devicemgr \
contrail-controller-config-dnsmasq \
contrail-controller-config-schema \
contrail-controller-config-svcmonitor \
contrail-controller-control-control \
contrail-controller-control-dns \
contrail-controller-control-named \
contrail-controller-webui-job \
contrail-controller-webui-web \
contrail-debug \
contrail-external-cassandra \
contrail-external-haproxy \
contrail-external-kafka \
contrail-external-rabbitmq \
contrail-external-redis \
contrail-external-rsyslogd \
contrail-external-stunnel \
contrail-external-zookeeper \
contrail-kubernetes-cni-init \
contrail-kubernetes-kube-manager \
contrail-node-init \
contrail-nodemgr \
contrail-openstack-compute-init \
contrail-openstack-heat-init \
contrail-openstack-neutron-init \
contrail-openstack-neutron-ml2-init \
contrail-provisioner \
contrail-status \
contrail-test-test \
contrail-tools \
contrail-tor-agent \
contrail-vrouter-agent \
contrail-vrouter-agent-dpdk \
contrail-vrouter-kernel-build-init \
contrail-vrouter-kernel-init \
contrail-vrouter-kernel-init-dpdk \
contrail-vrouter-plugin-mellanox-init-redhat \
contrail-vrouter-plugin-mellanox-init-ubuntu \
tf-ansible-deployer-src \
tf-build-manifest-src \
tf-charms-src \
tf-container-builder-src \
tf-deployment-test \
tf-helm-deployer-src \
tf-kolla-ansible-src \
tf-operator \
tf-operator-bundle
tf-operator-src \
tf-tripleo-heat-templates-src \
"

for image in $images ; do
  if ! sudo docker pull "opensdn-io/$image:$current_tag" ; then
    echo "ERROR: image opensdn-io/$image:$current_tag is not present in dockerhub"
  fi
done

echo "INFO: original list count:"
echo "$images" | wc -l
echo "INFO: pulled images count:"
sudo docker images | grep "$current_tag" | wc -l

new_images=$(sudo docker images | grep "$current_tag" | awk '{print $1}')
for image in $new_images ; do
  sudo docker tag $image:$current_tag $image:$new_tag
done

for image in $new_images ; do
  sudo docker push $image:$new_tag
done
