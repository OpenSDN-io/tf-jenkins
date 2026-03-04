#!/bin/bash -e

[ $# -ne 1 ] && exit 1

DIST=$1
BASEDIR=/var/local/mirror/repos/

envopts=" -e CI_DOMAIN=$CI_DOMAIN -e SLAVE_REGION=$SLAVE_REGION"

sudo docker run --rm --name ${DIST}repos -v ${BASEDIR}:/repos ${envopts} ${DIST}repos
