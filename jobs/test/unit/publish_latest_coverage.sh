#!/bin/bash
set -eo pipefail

[ "${DEBUG,,}" == "true" ] && set -x

SSH_OPTIONS="${SSH_OPTIONS:--T -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PasswordAuthentication=no}"

coverage_path="${LOGS_PATH}/${STREAM}/logs/coverage"
link_target="pipeline_${PIPELINE_NUMBER}/${STREAM}/logs/coverage"

ssh -i "${LOGS_HOST_SSH_KEY}" ${SSH_OPTIONS} \
  "${LOGS_HOST_USERNAME}@${LOGS_HOST}" \
  "test -d '${coverage_path}' && cd '${LOGS_PATH}/..' && ln -sfn '${link_target}' coverage"

stable_url="${LOGS_URL}/../coverage/"
echo "INFO: latest coverage published at ${stable_url}"
echo "INFO: HTML report: ${stable_url}coverage-html/index.html"
