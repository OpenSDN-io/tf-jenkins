#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

echo "INFO: prepare mirrors input"
mkdir -p ./src/opensdn-io/tf-dev-env/config/etc
cp pip.conf ./src/opensdn-io/tf-dev-env/config/etc/pip.conf
# TODO: add yum mirrors: base and docker

echo "INFO: run dev-env and sync sources"
./src/opensdn-io/tf-dev-env/run.sh fetch

echo "INFO: preapre deps for TPP compilation"
./src/opensdn-io/tf-dev-env/run.sh configure tpp

echo "INFO: Buil TPP"
./src/opensdn-io/tf-dev-env/run.sh compile tpp

cat <<EOF >/tmp/upload.sh
#!/bin/bash -e
echo "INFO: Upload packages"
for pfile in \$(find /root/work/RPMS -type f -name "*.rpm"); do
  package=\$(echo \$pfile | awk -F '/' '{print \$NF}')
  echo "INFO: Upload \$pfile as $package"
  curl -sS -u ${TPC_REPO_USER}:${TPC_REPO_PASS} --upload-file \$pfile $REPO_SOURCE/\$package
done
EOF
chmod a+x /tmp/upload.sh

echo "INFO: Copy upload script into container and run it"
sudo docker cp /tmp/upload.sh tf-dev-sandbox:/tmp/upload.sh
sudo docker exec tf-dev-sandbox /tmp/upload.sh
