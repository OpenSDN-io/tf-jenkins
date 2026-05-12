#Step by step guide for Openstack+Ceph deployment

Guide for deployment Openstack and ceph clusters with *kolla-ansible* and *cephadm*.
Openstack control-plane is running on one node only (non-HA configuration).

##Prerequsities

It's supposed that we have 6 or more baremetal nodes with installed Ubuntu Focal.
All nodes are available by ssh. All network interfaces and bonds are configured,
ip addresses are assigned and NTP is configured and works.

Network topology:
mgmt (public): 10.87.85.0/25 (gateway 10.87.85.126)
storage  bond1   20.10.10.0/24
tenant   ens2f1  20.10.30.0/24

All nodes have ip addresses in all the networks and can ping each other.

**Limitation**:
kolla-ansible can't assign neutron_external_interface to the same physical network interface which is used for public access.

**Workaround**: create bridge connected with physical public interface and connect veth pair to the bridge.
Assign public ip address to the bridge and use bridge interface as network_interface and veth2 as neutron_external_interface.

The nodes can be setup manully or with any automation.
ansible tool which can be used for this:
[ansible-netplan] (https://github.com/gleb108/ansible-netplan)

## Preparation
All actions should be done on the main node which is used for running ansible.
The same node will be used for deployment openstack control plane.
In this case it's tfci-node1 with public ip address 10.87.85.1.

Install ansible and kolla

```bash
apt update
apt install -y python3-dev libffi-dev gcc libssl-dev python3-pip
pip3 install git+https://opendev.org/openstack/kolla-ansible@stable/yoga
mkdir -p /etc/kolla
cp -r /usr/local/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
cp /usr/local/share/kolla-ansible/ansible/inventory/* .
git clone --branch stable/yoga https://opendev.org/openstack/kolla-ansible
pip3 install ./kolla-ansible

#the following command can fail if locale UTF-8 is not set
pip install -U 'ansible>=4,<6'
kolla-ansible install-deps
mkdir /etc/ansible
'''

Create file /etc/ansible/ansible.cfg

```
[defaults]
host_key_checking=False
pipelining=True
forks=100
```

Edit file /etc/hosts on every node
Every node itself should be assigned to 127.0.1.1 loopback (according ceph documentation)
Names of the node must coincide to their own hostnames (hostname -s)

```
127.0.1.1 tfci-node1.opensdn.io tfci-node1
#10.87.85.1 tfci-node1
10.87.85.2 tfci-node2
10.87.85.3 tfci-node3
10.87.85.4 tfci-node4
10.87.85.5 tfci-node5
10.87.85.6 tfci-node6
etc
```

Edit /etc/kolla/globals.yml and multinode (inventory) according to requirements
(See the example files in this directory)

Check ansible inventory and /etc/hosts

```bash
ansible -i multinode all -m ping
```

Bootstrap all the nodes
```bash
kolla-ansible -i multinode bootstrap-servers
```

## Deploying ceph cluster

Install cephadm and bootstrap initial ceph cluster

```bash
apt update; apt install -y cephadm ceph-common
cephadm bootstrap --mon-ip 10.87.85.1 --skip-monitoring-stack
ceph config set mon cluster_network 20.10.10.0/24
ceph config set global cluster_network 20.10.10.0/24
```
Copying ceph public key to the other nodes
```bash
ssh-copy-id -f -i /etc/ceph/ceph.pub root@tfci-node2
ssh-copy-id -f -i /etc/ceph/ceph.pub root@tfci-node3
etc
```

Add nodes to the cluster

```bash
ceph orch host add tfci-node2
ceph orch host add tfci-node3
ceph orch host add tfci-node4
ceph orch host add tfci-node5

ceph orch host label add tfci-node1 _admin
ceph orch host label add tfci-node2 _admin
ceph orch host label add tfci-node3 _admin
ceph orch host label add tfci-node4 _admin
ceph orch host label add tfci-node5 _admin

ceph orch host add tfci-node6

ceph orch device ls
ceph orch apply osd --all-available-devices
```

Install cephadm and ceph-common on the monitors
```bash
ssh tfci-node2 apt install -y cephadm ceph-common
ssh tfci-node3 apt install -y cephadm ceph-common
ssh tfci-node4 apt install -y cephadm ceph-common
ssh tfci-node5 apt install -y cephadm ceph-common
```

Enable autoscaling for pg number
```bash
ceph config set global osd_pool_default_pg_autoscale_mode on
```

Create pools, keyrings, credentials etc
for details see file kolla-ansible/doc/source/reference/storage/external-ceph-guide.rst

```bash
ceph osd pool create volumes
ceph osd pool create images
ceph osd pool create backups
ceph osd pool create vms

rbd pool init volumes
rbd pool init images
rbd pool init backups
rbd pool init vms

ceph auth get-or-create client.glance mon 'profile rbd' osd 'profile rbd pool=images' mgr 'profile rbd pool=images'
ceph auth get-or-create client.cinder mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=volumes, profile rbd pool=vms'
ceph auth get-or-create client.cinder-backup mon 'profile rbd' osd 'profile rbd pool=backups' mgr 'profile rbd pool=backups'

mkdir -p /etc/kolla/config/glance/
mkdir -p /etc/kolla/config/nova/
mkdir -p /etc/kolla/config/cinder/cinder-volume
mkdir -p /etc/kolla/config/cinder/cinder-backup

#Remove tabs from ceph.conf
sed -e 's/\t//g' -i /etc/ceph/ceph.conf

cp /etc/ceph/ceph.conf /etc/kolla/config/glance
cp /etc/ceph/ceph.conf /etc/kolla/config/cinder/
cp /etc/ceph/ceph.conf /etc/kolla/config/nova/

ceph auth get-or-create client.glance | tee /etc/kolla/config/glance/ceph.client.glance.keyring
ceph auth get-or-create client.cinder | tee /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring
cp /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder.keyring
cp /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring /etc/kolla/config/nova/ceph.client.cinder.keyring
ceph auth get-or-create client.cinder-backup | tee /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder-backup.keyring

cp /etc/kolla/config/glance/ceph.client.glance.keyring /etc/ceph/
cp /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring /etc/ceph/
cp /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder-backup.keyring /etc/ceph

scp /etc/ceph/* tfci-node2:/etc/ceph/
scp /etc/ceph/* tfci-node3:/etc/ceph/
scp /etc/ceph/* tfci-node4:/etc/ceph/
scp /etc/ceph/* tfci-node5:/etc/ceph/

```



## Deployment Openstack cluster

Generating password
```bash
kolla-genpwd
```

Make sure that kolla_internal_vip_address is assigned and pingable
```bash
kolla-ansible -i multinode prechecks
```
Deployment

```bash
kolla-ansible -i multinode deploy
```

Post-deployment steps
```bash
pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/yoga

kolla-ansible post-deploy
```

## Create cloud infrastructure

Authorization for openstack client
```bash
. /etc/kolla/admin-openrc.sh
```

1. Edit and use script *openstack_create_infra.sh* for creating infrastructure (networks, subnets, router and image)
It implies that you have file focal-server-cloudimg-amd64.img for ubuntu-focal glance image.

2. Use script *openstack_create_flavors.sh* for creating openstack flavors

3. Use commands from file *openstack_create_infra_instances.sh* for creating infra instances and for setup second volumes
inside the tf-mirrors and nexus instances.

4. Use commands from file *openstack_set_quotas.sh* for managing tenant quotes.




