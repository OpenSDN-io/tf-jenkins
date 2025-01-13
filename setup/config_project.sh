#!/bin/bash -ex

gerrit_user=$GERRIT_USER
gerrit_email=$GERRIT_EMAIL
gerrit_host=$GERRIT_HOST

dir=$PWD
cd /var/gerrit/

# config All-Projects for Verified
rm -rf gitproject
mkdir gitproject
cd gitproject
git init
git config --global user.email "$gerrit_email"
git config --global user.name "$gerrit_user"
git remote add origin "ssh://$gerrit_user@$gerrit_host:29418/All-Projects"
git fetch origin refs/meta/config:refs/remotes/origin/meta/config
git checkout meta/config
cp $dir/project.config ./
git commit -a -m "Added label - Verified"
git push origin meta/config:meta/config
cd ..
rm -rf gitproject

# fill repos
cd git
mkdir -p opensdn-io
cd opensdn-io

repos="tf-analytics \
tf-ansible-deployer \
tf-api-client \
tf-build \
tf-charms \
tf-common \
tf-container-builder \
tf-controller \
tf-deployment-test \
tf-dev-env \
tf-dev-test \
tf-devstack \
tf-dpdk \
tf-fabric-utils \
tf-heat-plugin \
tf-jenkins \
tf-kolla-ansible \
tf-neutron-plugin \
tf-nova-vif-driver \
tf-packages \
tf-specs \
tf-test \
tf-third-party \
tf-third-party-cache \
tf-third-party-packages \
tf-vnc \
tf-vrouter \
tf-web-controller \
tf-web-core \
tf-webui-third-party"

for repo in $repos ; do
    git clone --mirror git@github.com:opensdn-io/${repo}.git
done
