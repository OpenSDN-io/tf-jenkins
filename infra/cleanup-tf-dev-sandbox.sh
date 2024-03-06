#!/bin/bash -e

# howto: https://support.sonatype.com/hc/en-us/articles/360009696054-How-to-delete-docker-images-from-Nexus-Repository-Manager

nexus_rest_url="http://nexus.$SLAVE_REGION.$CI_DOMAIN/service/rest/v1"
registries="tungsten_ci tungsten_gate_cache"
image_name="tf-dev-sandbox"

if [[ -n $GERRIT_PROJECT && $GERRIT_PROJECT != 'opensdn-io/tf-dev-env' ]] ; then
  exit 0
fi

for registry in $registries ; do
  echo "INFO: registry = ${registry}"
  for id in $(curl -sS "${nexus_rest_url}/search?repository=${registry}&name=${image_name}" | jq -r .items[].id) ; do
    echo "INFO: id = $id"
    curl -sS -X DELETE "${nexus_rest_url}/components/${id}"
  done
done

echo "INFO: image ${image_name} has been deleted from registries"
