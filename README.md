# TF Jenkins

TF Jenkins is a common name of whole infra which serves:

- checking and gating for reviews from <https://gerrit.opensdn.io>
- running various checks for whole functionality (nightly)
- publishing artifacts to dockerhub

Whole infrastructure also has Nexus, some VM-s for mirrors, slaves for Jenkins, host for aquasec, logs storage, grafana for monitoring.

## Infra details

Whole infra deployment should be stored as ansible scripts github (URL: TODO)
For now it's a bit outdated - we're working on actualisation.

### Jenkins master

Ubuntu 18.04 based VM, 4 CPU, 16 Gb RAM, 300Gb for root volume.
URL: <https://jenkins.opensdn.io/>
Source code: <https://github.com/opensdn-io/tf-jenkins>

Jenkins master is deployed as a docker container. All further configuration (user, plugins, ...) is applied inside Jenkins itself.

Architecture of CI code requires Jenkins slave with mirrors in the same private network.

### Jenkins slave

Ubuntu 18.04 based VM, 8 CPU, 32 Gb RAM, 300Gb for root volume.

To be able to create/remove workers/networks infra must have individual slave in each region.

For now we have only one slave in one region of openstack. But we checked that code can work with different slave on AWS.

### Nexus

Ubuntu 18.04 based VM, 4 CPU, 16 Gb RAM, 1Tb for root volume, 2Tb for /var/lib/docker.
URL: <http://nexus.opensdn.io/>

For now it serves:

- docker registry on port 5101 (5001 the same without SSL) - used for short lived images with different tags like review images. Images are stored for 24 hours - then they are removed.
- docker registry on port 5102 (5002 the same without SSL) - used for long lived images with constant tags like 'latest', 'nightly', 'R2011', ...
- raw hosted folder 'images' - used for VM images for sanity tests. It has some predeployed content which is saved on S3.
- raw hosted folder 'contrail_third_party' - used as a local cache to resources from files <https://github.com/opensdn-io/tf-third-party/blob/master/packages.xml> and <https://github.com/opensdn-io/tf-webui-third-party/blob/master/packages.xml> to avoid network glitches in CI
- YUM repo for 'TPC binary' - third-party cache of static yum packages. These packages were taken long time ago somewhere and there is no source code for them. So this repo has predeployed content which saved on S3.
- YUM repo for 'TPC source' - third-party cache of built yum packages. Source spec files for these RPM-s are stored in <https://github.com/opensdn-io/tf-third-party-packages> and this repo can be fully re-built from scratch. It's used when product needs some yum package which is not available as yum package - only sources or pyhton package is present.
- Some maven repos with predefined content in one of them. But knowledge why it's required is absent.

Nginx is deployed on nexus to provide https access to those CI registries on ports 5101 and 5102 respectively. Registries on ports 5101 and 5102 are not secured.

### Logs storage

Currently resides on Nexus VM.
URL: <http://nexus.opensdn.io:8082/jenkins_logs/>

Contains logs for most jobs. Divived into nightly, review, infra folders.
Clean up policy - one month.

### Grafana

Resides on VM with Jenkins.
URL: <http://monitoring.opensdn.io/>

First purpose is to show TF build matrix - table which shows live status of TF from nightly builds.
Second purpose is to show checking and gating status for reviews.

### Aquasec

TODO.

Centos 7 based VM, 2 CPU, 8 Gb RAM.

Hosts software from <https://www.aquasec.com/> and uses for collecting reports about vulnerabilities.

### Mirrors

Ubuntu 18.04 based VM, 4 CPU, 16 Gb RAM, 200Mb for root volume, 2Tb for /var/local/mirror

Contains various mirrors of yum, pip, apt, docker, ...

## Support of https://gerrit.opensdn.io

We provide the ability to run jobs to check your patchsets sent for review.
We have similar terminology as OpenStack CI - checking and gating ('check' and 'gate' pipelines).

Each project is associated with several templates that are launched by default when a new patchset is loaded. You can see the list of projects and associated templates in the `config/main.yaml` file. Each project has two 'pipelines' - 'check' and  'gate'.
'check' pipeline is intended as a set of simple checks and fast as possible. By this we achieve less workload fo CI cause each patchset in most cases has more runs of 'check' than 'gate'. And second reason then developer gets result of its change fast.
'gate' pipeline has more jobs to check in most cases. And it's longer than 'check'. It happens cause it must recompile source code against current base, current and dependent patchsets, and patchsets which are present in 'gate' pipeline right now. CI has to take into account current runs in 'gate' cause superposition with current patchset may lead to broken code. Also 'gate' pipeline stores built docker images in local cache for 1 day to use them in CI runs for deployment projects to speed up checking. Such images we called 'frozen'. They have appropriate image tag.

Checking is started by Jenkins for each new patchset. To independently initiate the review of templates related to the current project, add a comment `check` to your review.

To start checking a specific template, add a comment to your review with template name like `check template template-name`. For several templates at once comment is `check templates name1 name2`.
It's also possible to add params for template with: 'check template ansible-os ansible-os(ENVIRONMENT_OS:ubuntu20) ansible-os(OPENSTACK_VERSION:ussuri)'. It's like a function call.

Gating is started when gerrit labels are set to specific values. To start or restart gating comment is `gate`.

It is possible to stop all jobs running for the current review. To do this, add a comment `cancel` to your review.

TF CI supports `Depends-On: I...` parameter in commit message. It should contain Commit-Id of dependent review. In this case CI cherry-picks both change sets into sources tree and run jobs with merged content. It calls explicit dependency. This technique is applicable for any tree of dependent reviews but this tree must not have circular dependencies.
Another option is implicit dependency - it's a dependency based on git tree. You can upload several commits for one repo at time - they will be shown in gerrit as a relation chain. And CI will take changes from parent commits by SHA for checking.
If that review that current depends on gets new patchset then checks for current review will be cancelled.

After checking TF CI posts a message with results along with timings, links to logs. Overall time is a time for whole checking. And stream time is a summarized time from all jobs in this stream. Sometimes stream time can be bigger that checks time due to parallel runs.

General workflow of gerrit assumes working with labels - <https://gerrit-review.googlesource.com/Documentation/config-labels.html>
Current implementation is following: People sets only 'Code-Review' and 'Approved' label at anytime of review lifecycle - sometimes just one person can do it, sometimes project has agreement to wait for two people. It's possible to reset label's value back to any other value to stop merging or if person changes the opinion.
‘Verified’ label is set by CI: +1/-1 for checking and +2/-2 for gating. '+1' means that basic checks passed against current sourcecode state plus current (and dependent) patchset. When Code-Review is +2 and Approved is +1 then CI starts gating. If it’s successful then CI sets +2 for Verified and then merges the change.

## Used tools

Various tools were used to build artifacts, set up TF, and test it. Please read README-s in these projects for more information.

<https://github.com/opensdn-io/tf-dev-env>
This project is used for creation of TF's docker images.

<https://github.com/opensdn-io/tf-devstack>
This project is used for various deployment scenarios.

<https://github.com/opensdn-io/tf-dev-test>
This project is used for running concrete test suite - tf-test (also called as sanity) and tf-deployment-test (see below).

<https://github.com/opensdn-io/tf-deployment-test>
This project contains various deployment test like ZIU, etc.
