#!/usr/bin/env bash

set -o pipefail -o errexit -o nounset

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"

RDS_INSTANCE_ID="instance1"

GITHUB_OWNER="pellepelster"
GITHUB_REPOSITORY="hetzner-rds-postgres"

DOCKER_REGISTRY="docker.pkg.github.com"
DOCKER_REPOSITORY="${GITHUB_OWNER}/${GITHUB_REPOSITORY}"
DOCKER_IMAGE_NAME="hetzner-rds-postgres"

source "${DIR}/ctuhl/lib/shell/log.sh"
source "${DIR}/ctuhl/lib/shell/ruby.sh"

PASS_CLOUD_API_TOKEN="infrastructure/rds/${RDS_INSTANCE_ID}/cloud_api_token"
PASS_GITHUB_RW_TOKEN="github/${GITHUB_OWNER}/personal_access_token_rw"
PASS_GITHUB_RO_TOKEN="github/${GITHUB_OWNER}/personal_access_token_ro"

PASS_INSTANCE_ECDSA_KEY="infrastructure/rds/${RDS_INSTANCE_ID}/ssh_host_ecdsa_key"
PASS_INSTANCE_ECDSA_PUB="infrastructure/rds/${RDS_INSTANCE_ID}/ssh_host_ecdsa_public_key"
PASS_INSTANCE_RSA_KEY="infrastructure/rds/${RDS_INSTANCE_ID}/ssh_host_rsa_key"
PASS_INSTANCE_RSA_PUB="infrastructure/rds/${RDS_INSTANCE_ID}/ssh_host_rsa_public_key"
PASS_INSTANCE_ED25519_KEY="infrastructure/rds/${RDS_INSTANCE_ID}/ssh_host_ed25519_key"
PASS_INSTANCE_ED25519_PUB="infrastructure/rds/${RDS_INSTANCE_ID}/ssh_host_ed25519_public_key"

TEMP_DIR="${DIR}/.tmp"
mkdir -p "${TEMP_DIR}"

trap task_clean SIGINT SIGTERM ERR EXIT

function task_docker_login {
  ensure_docker_login
}

function ensure_docker_login {
  pass "${PASS_GITHUB_RW_TOKEN}" | docker login https://docker.pkg.github.com -u ${GITHUB_OWNER} --password-stdin
}

function generate_ssh_identity {
  local type="${1:-}"
  local pass_key_path="${2:-}"
  local pass_pub_path="${3:-}"
  ssh-keygen -q -N "" -t "${type}" -f "${TEMP_DIR}/ssh_host_${type}_key"
  pass insert -m "${pass_key_path}" < "${TEMP_DIR}/ssh_host_${type}_key"
  pass insert -m "${pass_pub_path}" < "${TEMP_DIR}/ssh_host_${type}_key.pub"
}


function task_generate_ssh_identities {
  generate_ssh_identity "ed25519" "${PASS_INSTANCE_ECDSA_KEY}" "${PASS_INSTANCE_ECDSA_PUB}"
  generate_ssh_identity "ecdsa" "${PASS_INSTANCE_RSA_KEY}" "${PASS_INSTANCE_RSA_PUB}"
  generate_ssh_identity "rsa" "${PASS_INSTANCE_ED25519_KEY}" "${PASS_INSTANCE_ED25519_PUB}"
}

function task_build {
  docker build -t ${DOCKER_IMAGE_NAME} -f Dockerfile .
  docker tag "${DOCKER_IMAGE_NAME}" "${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/${DOCKER_IMAGE_NAME}:latest"
}

function task_usage {
  echo "Usage: $0 build | test | deploy"
  exit 1
}

function task_clean {
  log_divider_header "cleaning up..."

  rm -rf "${TEMP_DIR}"

  cd "${DIR}/test/rds"
  docker-compose rm --force --stop -v

  docker volume rm -f rds_rds-data
  docker volume rm -f rds_rds-backup

  log_divider_footer
}

function terraform_wrapper_do() {

  log_divider_header "executing terraform..."

  local directory=${1:-}
  local command=${2:-apply}
  shift || true
  shift || true

  if [ ! -d "${directory}/.terraform" ]; then
    terraform_wrapper "${directory}" init -lock=false
  fi

  terraform_wrapper "${directory}" "${command}" -lock=false "$@"
  log_divider_footer
}

function terraform_wrapper() {
  local directory=${1:-}
  shift || true
  (
      cd "${DIR}/${directory}"
      terraform "$@"
  )
}

function task_infra_instance {
  export TF_VAR_github_token="$(pass ${PASS_GITHUB_RO_TOKEN})"
  export TF_VAR_github_owner="${GITHUB_OWNER}"
  export TF_VAR_rds_instance_id="${RDS_INSTANCE_ID}"
  export TF_VAR_cloud_api_token="$(pass ${PASS_CLOUD_API_TOKEN})"
  export TF_VAR_ssh_identity_ecdsa_key="$(pass "${PASS_INSTANCE_ECDSA_KEY}" | base64 -w 0)"
  export TF_VAR_ssh_identity_ecdsa_pub="$(pass "${PASS_INSTANCE_ECDSA_PUB}" | base64 -w 0)"
  export TF_VAR_ssh_identity_rsa_key="$(pass "${PASS_INSTANCE_RSA_KEY}" | base64 -w 0)"
  export TF_VAR_ssh_identity_rsa_pub="$(pass "${PASS_INSTANCE_RSA_PUB}" | base64 -w 0)"
  export TF_VAR_ssh_identity_ed25519_key="$(pass "${PASS_INSTANCE_ED25519_KEY}" | base64 -w 0)"
  export TF_VAR_ssh_identity_ed25519_pub="$(pass "${PASS_INSTANCE_ED25519_PUB}" | base64 -w 0)"

  terraform_wrapper_do "terraform/instance" "$@"
}


function ensure_environment {

  if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
    echo "expected an ssh public key at ~/.ssh/id_rsa.pub for instance provisioning"
    exit 1
  fi

  if ! pass ${PASS_CLOUD_API_TOKEN} &> /dev/null; then
    echo "no cloud api token found at pass path '${PASS_CLOUD_API_TOKEN}'"
    exit 1
  fi

  if ! pass ${PASS_GITHUB_RW_TOKEN} &> /dev/null; then
    log_error "no personal github r/w token found at pass path '${PASS_GITHUB_RW_TOKEN}', can be set via './do set-github-access-token-rw'"
    exit 1
  fi

  if ! pass ${PASS_GITHUB_RO_TOKEN} &> /dev/null; then
    log_error "no personal github r/o token found at pass path '${PASS_GITHUB_RO_TOKEN}', can be set via './do set-github-access-token-ro'"
    exit 1
  fi

  local ssh_pass_missing=0

  for ssh_pass_path in PASS_INSTANCE_ECDSA_KEY \
      PASS_INSTANCE_ECDSA_PUB \
      PASS_INSTANCE_RSA_KEY \
      PASS_INSTANCE_RSA_PUB \
      PASS_INSTANCE_ED25519_KEY \
      PASS_INSTANCE_ED25519_PUB; do

      if ! pass ${!ssh_pass_path} &> /dev/null; then
        ssh_pass_missing=1
      fi
  done

  if [[ ${ssh_pass_missing} == 1 ]]; then
    log_error "no ssh identity information found at pass path '${!ssh_pass_path}', can be generated via './do generate-ssh-identities'"
    exit 1
  fi
}

function task_infra_storage {
  ensure_environment

  export TF_VAR_rds_instance_id="${RDS_INSTANCE_ID}"
  export TF_VAR_cloud_api_token="$(pass ${PASS_CLOUD_API_TOKEN})"

  terraform_wrapper_do "terraform/storage" "$@"
}

function task_ssh_instance {
  local public_ip="$(terraform_wrapper "terraform/instance" "output" "-json" | jq -r '.public_ip.value')"
  ssh root@${public_ip} "$@"
}

function task_test() {
  (
    cd ${DIR}/test
    cthul_ruby_ensure_bundle
    bundle exec ruby runner.rb rds "$@"
  )
}

function task_run() {
  (
    cd ${DIR}/test/rds
    docker-compose up -d rds-test1
    local psql_port="$(docker inspect rds_rds-test1_1 | jq -r '.[0].NetworkSettings.Ports["5432/tcp"][0].HostPort')"
    echo "rds postgres is running at psql://localhost:${psql_port}"
    echo "press any key to shutdown"
    read
  )
}

function task_deploy {
  ensure_environment
  ensure_docker_login
  docker push "${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/${DOCKER_IMAGE_NAME}:latest"
}

function task_set_github_access_token_rw {
  echo "Enter the Github personal read/write access token, followed by [ENTER]:"
  read -r github_access_token
  echo ${github_access_token} | pass insert -m "${GITHUB_RW_TOKEN}"
}

function task_set_github_access_token_ro {
  echo "Enter the Github personal readonly access token, followed by [ENTER]:"
  read -r github_access_token
  echo ${github_access_token} | pass insert -m "${GITHUB_RO_TOKEN}"
}

function task_set_cloud_api_token {
  echo "Enter the Hetzner Cloud API token, followed by [ENTER]:"
  read -r hetzner_cloud_api_token
  echo ${hetzner_cloud_api_token} | pass insert -m "infrastructure/${DOMAIN}/cloud_api_token"
}

ARG=${1:-}
shift || true
case ${ARG} in
  build) task_build "$@" ;;
  run) task_run "$@" ;;
  test) task_test "$@" ;;
  deploy) task_deploy "$@" ;;
  infra-instance) task_infra_instance "$@" ;;
  infra-storage) task_infra_storage "$@" ;;
  ssh-instance) task_ssh_instance "$@" ;;
  generate-ssh-identities) task_generate_ssh_identities ;;
  set-github-access-token-rw) task_set_github_access_token_rw ;;
  set-github-access-token-ro) task_set_github_access_token_ro ;;
  set-cloud-api-token) task_set_cloud_api_token ;;
  docker-login) task_docker_login ;;
  *) task_usage ;;
esac
