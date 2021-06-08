#!/bin/bash -e

[ $# -ne 1 ] && exit 1

declare -A REPOS=( \
    ["centos7"]="centos7 yum7" \
    ["rhel7"]="rhel7 ubi7" \
    ["rhel8"]="rhel8 ubi8" \
    ["ubuntu"]="ubuntu" \
)

for repo in ${REPOS[$1]} ; do
    echo "INFO: publish repo $repo for dist $1"
    pushd /var/local/mirror/repos/${repo}
    new_latest=$(readlink stage)
    if [ -d latest ]; then
        old_latest=$(readlink latest)
    fi
    sudo rm -f latest || /bin/true
    sudo ln -s ${NEWLATEST} latest
    if [[ -n "$old_latest" ]]; then
        sudo rm -rf $old_latest
    fi
    popd
done
