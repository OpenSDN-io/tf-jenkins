#!/bin/bash -e

[ $# -ne 1 ] && exit 1

declare -A REPOS=( \
    ["centos7"]="centos7 yum7" \
    # ["centos8"]="centos8 yum8" \
    # ["rhel7"]="rhel7 ubi7" \
    # ["rhel82"]="rhel82 ubi82" \
    # ["rhel84"]="rhel84 ubi84" \
    ["ubuntu"]="ubuntu" \
    ["rocky9"]="rocky9 yum9" \
)

for repo in ${REPOS[$1]} ; do
    echo "INFO: publish repo $repo for dist $1"
    pushd /var/local/mirror/repos/${repo}
    new_latest=$(readlink stage)
    if [ -d latest ]; then
        old_latest=$(readlink latest)
    fi
    sudo rm -f latest || /bin/true
    sudo ln -s ${new_latest} latest
    if [[ -n "$old_latest" && "$old_latest" != "$new_latest" ]]; then
        sudo rm -rf $old_latest
    fi
    popd
done
