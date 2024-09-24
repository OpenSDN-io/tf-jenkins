#!/bin/bash -e

REPOS_ROCKY9=(baseos baseos-debug baseos-source appstream appstream-debug appstream-source crb crb-source crb-debug)
REPOS_YUM9=(dockerrepo epel)
MIRRORDIR=/repos
DATE=$(date +"%Y%m%d")

# exclude huge debuginfo
echo "exclude=firefox-debuginfo* kde*debuginfo* java*debuginfo* kernel*debuginfo* webkit*debuginfo* libre*debuginfo* thunderbird*debuginfo* llvm*debuginfo* xulrunner*debuginfo* qt*debuginfo*" >> /etc/yum.conf

echo "INFO: preparing temp folders for downloading"
for repo in "rocky9" "yum9" ; do
  if [ ! -d ${MIRRORDIR}/$repo/${DATE} ]; then
    mkdir -p ${MIRRORDIR}/$repo/${DATE}
    if [ -d ${MIRRORDIR}/$repo/latest ]; then
      echo "INFO: Copying current latest for repo $repo to stage to speed up reposync"
      cp -R ${MIRRORDIR}/$repo/latest/* ${MIRRORDIR}/$repo/${DATE}/
        echo "INFO: Copied"
    fi
  fi
done

for r in ${REPOS_ROCKY9[@]}; do
  echo "INFO: updating rocky9 repoid=$r"
  reposync --repoid=${r} --download-metadata --downloadcomps -p ${MIRRORDIR}/rocky9/${DATE}
  createrepo -v ${MIRRORDIR}/rocky9/${DATE}/${r}/
done

for r in ${REPOS_YUM9[@]}; do
  echo "INFO: updating yum9 repoid=$r"
  reposync --repoid=${r} --download-metadata --downloadcomps -p ${MIRRORDIR}/yum9/${DATE}
  createrepo -v ${MIRRORDIR}/yum9/${DATE}/${r}/
done

echo "INFO: switching dowloaded repos to stage"
for repo in "rocky9" "yum9" ; do
  pushd ${MIRRORDIR}/$repo
  rm -f stage
  ln -s ${DATE} stage
  popd
done
