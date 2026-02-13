#!/bin/bash -eE
set -o pipefail

# NOTE: do not run dnf update - it ups kernel version which is not suported !

sudo dnf install -y bind bind-utils haproxy httpd net-tools
