#!/bin/bash -e

REPOS_CENTOS7=(base centosplus extras updates centos-sclo-rh base-debuginfo cloud)
REPOS_YUM7=(centos-openstack-queens dockerrepo epel k8s)
MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

# exclude huge debuginfo
echo "exclude=firefox-debuginfo* kde*debuginfo* java*debuginfo* kernel*debuginfo* webkit*debuginfo* libre*debuginfo* thunderbird*debuginfo* llvm*debuginfo* xulrunner*debuginfo* qt*debuginfo*" >> /etc/yum.conf

echo "INFO: preparing temp folders for downloading"
for repo in "centos7" "yum7" ; do
  if [ ! -d ${MIRRORDIR}/$repo/${DATE} ]; then
    mkdir -p ${MIRRORDIR}/$repo/${DATE}
    if [ -d ${MIRRORDIR}/$repo/latest ]; then
      echo "INFO: Copying current latest for repo $repo to stage to speed up reposync"
      cp -R ${MIRRORDIR}/$repo/latest/* ${MIRRORDIR}/$repo/${DATE}/
        echo "INFO: Copied"
    fi
  fi
done

for r in ${REPOS_CENTOS7[@]}; do
  echo "INFO: updating centos7 repoid=$r"
  reposync -l --repoid=${r} --download-metadata --downloadcomps --download_path=${MIRRORDIR}/centos7/${DATE}
  createrepo -v ${MIRRORDIR}/centos7/${DATE}/${r}/
done

for r in ${REPOS_YUM7[@]}; do
  echo "INFO: updating yum7 repoid=$r"
  reposync -l --repoid=${r} --download-metadata --downloadcomps --download_path=${MIRRORDIR}/yum7/${DATE}
  createrepo -v ${MIRRORDIR}/yum7/${DATE}/${r}/
done

echo "INFO: switching dowloaded repos to stage"
for repo in "centos7" "yum7" ; do
  pushd ${MIRRORDIR}/$repo
  rm -f stage
  ln -s ${DATE} stage
  popd
done
