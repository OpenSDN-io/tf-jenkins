#!/bin/bash -e

current_tag=$1
new_tag=$2

if [[ -z "current_tag" || -z "new_tag" ]]; then
  echo "ERROR: please specify tag: docker_tag.sh latest release-1"
  exit 1
fi

docker login

images="\
opensdn-analytics-alarm-gen \
opensdn-analytics-api \
opensdn-analytics-collector \
opensdn-analytics-query-engine \
opensdn-analytics-snmp-collector \
opensdn-analytics-snmp-topology \
opensdn-controller-config-api \
opensdn-controller-config-devicemgr \
opensdn-controller-config-dnsmasq \
opensdn-controller-config-schema \
opensdn-controller-config-svcmonitor \
opensdn-controller-control-control \
opensdn-controller-control-dns \
opensdn-controller-control-named \
opensdn-controller-webui-job \
opensdn-controller-webui-web \
opensdn-debug \
opensdn-external-cassandra \
opensdn-external-haproxy \
opensdn-external-kafka \
opensdn-external-rabbitmq \
opensdn-external-redis \
opensdn-external-rsyslogd \
opensdn-external-stunnel \
opensdn-external-zookeeper \
opensdn-kubernetes-cni-init \
opensdn-kubernetes-kube-manager \
opensdn-node-init \
opensdn-nodemgr \
opensdn-openstack-compute-init \
opensdn-openstack-heat-init \
opensdn-openstack-neutron-init \
opensdn-provisioner \
opensdn-status \
opensdn-test-test \
opensdn-tools \
opensdn-tor-agent \
opensdn-vrouter-agent \
opensdn-vrouter-agent-dpdk \
opensdn-vrouter-kernel-build-init \
opensdn-vrouter-kernel-init \
opensdn-vrouter-kernel-init-dpdk \
opensdn-ansible-deployer-src \
opensdn-build-manifest-src \
opensdn-charms-src \
opensdn-container-builder-src \
opensdn-deployment-test \
opensdn-kolla-ansible-src \
"

for image in $images ; do
  if ! sudo docker pull "opensdn/$image:$current_tag" ; then
    echo "ERROR: image opensdn/$image:$current_tag is not present in dockerhub"
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
