#!/usr/bin/env bash

set -o pipefail -o errexit -o nounset

echo "complete" > /rds/run/recovery_complete
