#!/bin/bash -e
set -o pipefail

[ "${DEBUG,,}" == "true" ] && set -x

sudo yum install -y wget curl skopeo

echo "INFO: prepare list of docker image to cache from tf-devstack"
./src/opensdn-io/tf-devstack/common/get_image_cache.sh $(pwd)/imagelist

imagelist=$(pwd)/imagelist
for image in $(cat $imagelist); do
  imagename=$(echo $image | cut -d '/' -f 2-3)
  skopeo copy --dest-tls-verify=false docker://$image docker://$DOCKER_MIRROR/$imagename
done
