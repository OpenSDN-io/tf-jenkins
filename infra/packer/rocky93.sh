#!/bin/bash -eE
set -o pipefail

# NOTE: do not run dnf update - it ups kernel version which is not suported !

sudo dnf install -y bind bind-utils haproxy httpd net-tools

# cloud-init 23.1.1 on Rocky 9.3 fails to generate SSH host keys on first boot,
# causing sshd to fail. Update cloud-init to fix this.
sudo dnf update -y cloud-init
