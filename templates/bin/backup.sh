#!/usr/bin/env bash

set -o pipefail -o errexit -o nounset

pgbackrest --config /rds/config/pgbackrest.conf --log-level-console=info --log-path=/rds/log --stanza={{ .Env.DB_INSTANCE_ID }} backup --type=full