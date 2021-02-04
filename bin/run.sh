#!/usr/bin/env bash

set -o pipefail -o errexit -o nounset

export DB_USERNAME=${DB_USERNAME:-$DB_INSTANCE_ID}
export DB_DATABASE=${DB_DATABASE:-$DB_INSTANCE_ID}

export INSTANCE_DATA_DIR="${DATA_DIR}/${DB_INSTANCE_ID}"
export DB_BACKUP_DIR="${BACKUP_DIR}/${DB_INSTANCE_ID}"

if [ -z "${DB_PASSWORD}" ]; then
  DB_PASSWORD=$(uuidgen)
  echo "no password set, setting random password '${DB_PASSWORD}"
fi

mkdir -p "${INSTANCE_DATA_DIR}"
mkdir -p "${DB_BACKUP_DIR}"

chown ${USER_ID}:${USER_GID} "${INSTANCE_DATA_DIR}"
chmod 700 "${INSTANCE_DATA_DIR}"

chown ${USER_ID}:${USER_GID} "${DB_BACKUP_DIR}"
chmod 700 "${DB_BACKUP_DIR}"

mkdir -p /rds/{socket,log,run,bin}

# snippet:run_gomplate
gomplate --input-dir /rds/templates/config --output-dir /rds/config
gomplate --input-dir /rds/templates/bin --output-dir /rds/bin
# /snippet:run_gomplate

POSTGRES_BASE_DIR="/usr/lib/postgresql/11"
POSTGRES_BIN_DIR="${POSTGRES_BASE_DIR}/bin"

function psql_execute() {
    local query=${1:-}
    psql -h /rds/socket postgres --field-separator-zero --record-separator-zero --tuples-only --quiet -c "${query}"
}

function pgbackrest_execute() {
    pgbackrest --config /rds/config/pgbackrest.conf --log-path=/rds/log --stanza=${DB_INSTANCE_ID} "$@"
}

function psql_count() {
    psql_execute "$@" | tr -d '[:space:]'
}

function init_db() {

    # snippet:run_initdb
    ${POSTGRES_BIN_DIR}/initdb --username="rds" --encoding=UTF8 --pwfile=<(echo "${DB_PASSWORD}") -D "${INSTANCE_DATA_DIR}" || true
    # /snippet:run_initdb

    cp /rds/config/postgresql.conf "${INSTANCE_DATA_DIR}/postgresql.conf"
    cp /rds/config/pg_hba.conf "${INSTANCE_DATA_DIR}/pg_hba.conf"

    # make sure we only listen public when DB is ready to go
    # snippet:run_init_start
    ${POSTGRES_BIN_DIR}/pg_ctl -D "${DATA_DIR}/${DB_INSTANCE_ID}" start --options="-c listen_addresses=''"
    # /snippet:run_init_start

    if [[ $(pgbackrest_status_code) -gt 0 ]]; then

        if [[ "$(ls -A ${BACKUP_DIR}/${DB_INSTANCE_ID})" ]]; then
            local invalid_backups_dir="${BACKUP_DIR}/${DB_INSTANCE_ID}/.invalid_backups_$(date +%Y%m%d%H%M%S)"
            mkdir -p "${invalid_backups_dir}"
            mv ${BACKUP_DIR}/${DB_INSTANCE_ID}/* "${invalid_backups_dir}"
        fi
    fi

    pgbackrest --config /rds/config/pgbackrest.conf --log-path=/rds/log --stanza=${DB_INSTANCE_ID} stanza-create

    # snippet:run_create_db
    if [[ $(psql_count "SELECT count(datname) FROM pg_database WHERE datname = '${DB_DATABASE}';") == "0" ]]; then
        psql_execute "CREATE DATABASE ${DB_DATABASE}"
    fi
    # /snippet:run_create_db

    # snippet:run_create_user
    if [[ $(psql_count "SELECT count(u.usename) FROM pg_catalog.pg_user u WHERE u.usename = '${DB_USERNAME}';") == "0" ]]; then
        psql_execute "CREATE USER ${DB_USERNAME} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}'"
    fi

    psql_execute "GRANT ALL PRIVILEGES ON DATABASE ${DB_DATABASE} TO ${DB_USERNAME}"
    # /snippet:run_create_user

    echo "executing initial backup"
    # snippet:run_init_finalize
    pgbackrest_execute --log-level-console=info backup

    ${POSTGRES_BIN_DIR}/pg_ctl -D "${INSTANCE_DATA_DIR}" stop
    # /snippet:run_init_finalize
}

function pgbackrest_status_code() {
    PGBACKREST_INFO="$(pgbackrest_execute --output=json info)"

    if  [[ $(echo ${PGBACKREST_INFO} | jq length) -gt 0 ]]; then
        BACKUP_INFO=$(echo ${PGBACKREST_INFO} | jq ".[] | select(.name == \"${DB_DATABASE}\")")
        echo ${BACKUP_INFO} | jq -r '.status.code'
    else
        echo "99"
    fi
}

if [[ "$(ls -A "${INSTANCE_DATA_DIR}")" ]]; then
    echo "data dir is not empty"
    rm -f /rds/socket/*
    rm -f "${INSTANCE_DATA_DIR}/postmaster.pid"

    # snippet:run_start_with_data
    ${POSTGRES_BIN_DIR}/pg_ctl -D "${INSTANCE_DATA_DIR}" start --options="-c listen_addresses=''"
    psql_execute "ALTER USER ${DB_USERNAME} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}'"
    ${POSTGRES_BIN_DIR}/pg_ctl -D "${INSTANCE_DATA_DIR}" stop
    # /snippet:run_start_with_data
else
    echo "data dir is empty"

    if [[ $(pgbackrest_status_code) -eq 0 ]]; then

        echo "restoring database from backup"
        # snippet:run_restore_restore
        pgbackrest_execute --db-path="${INSTANCE_DATA_DIR}" restore --recovery-option="recovery_end_command=/rds/bin/recovery_complete.sh"
        # /snippet:run_restore_restore

        sleep 5

        echo "starting db for recovery"
        # snippet:run_recovery
        ${POSTGRES_BIN_DIR}/pg_ctl -D "${INSTANCE_DATA_DIR}" start --options="-c listen_addresses=''"

        while [[ -f /rds/run/recovery_complete ]]; do
            echo "waiting for recovery completion"
            sleep 5
        done
        # /snippet:run_recovery

        # snippet:run_recovery_finish
        until [[ "$(psql_execute 'SELECT pg_is_in_recovery();' | tr -d '[:space:]')" == "f" ]]; do
            echo "waiting for server to be ready"
            sleep 5
        done
        psql_execute "ALTER USER ${DB_USERNAME} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}'"

        ${POSTGRES_BIN_DIR}/pg_ctl -D "${INSTANCE_DATA_DIR}" stop
        # /snippet:run_recovery_finish
    else
        init_db
    fi
fi

echo "starting postgres db"
# snippet:run_start
exec ${POSTGRES_BIN_DIR}/postgres -D "${INSTANCE_DATA_DIR}"
# /snippet:run_start
