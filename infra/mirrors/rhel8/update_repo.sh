#!/bin/bash -ex

mkdir -p /var/www/html/repos/{ansible,datapath,openstack,ha,satellite}

reposync  -p /var/www/html/repos/ansible --download-metadata --repo=ansible-2-for-rhel-8-x86_64-rpms
reposync  -p /var/www/html/repos/ansible --download-metadata  --repo=ansible-2.8-for-rhel-8-x86_64-rpms   

reposync  -p /var/www/html/repos/datapath --download-metadata  --repo=fast-datapath-for-rhel-8-x86_64-rpms 

reposync  -p /var/www/html/repos/openstack --download-metadata  --repo=openstack-16.1-for-rhel-8-x86_64-rpms
reposync  -p /var/www/html/repos/openstack --download-metadata  --repo=openstack-16-for-rhel-8-x86_64-rpms  

reposync  -p /var/www/html/repos/ha --download-metadata  --repo=rhel-8-for-x86_64-highavailability-rpms
reposync  -p /var/www/html/repos/satellite --download-metadata  --repo=satellite-tools-6.5-for-rhel-8-x86_64-rpms