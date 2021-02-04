FROM debian:buster-slim

ENV DB_INSTANCE_ID=""
ENV DB_PASSWORD=""

ENV USER=rds
ENV USER_ID=4000
ENV USER_GID=4000
ENV DATA_DIR=/storage/data
ENV BACKUP_DIR=/storage/backup

ENV GOMPLATE_VERION="v3.8.0"
ENV GOMPLATE_CHECKSUM="847f7d9fc0dc74c33188c2b0d0e9e4ed9204f67c36da5aacbab324f8bfbf29c9"

# snippet:docker_install_packages
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get dist-upgrade --assume-yes --quiet && \
    apt-get --assume-yes --quiet --no-install-recommends install \
    postgresql-11 \
    curl \
    ca-certificates \
    jq \
    uuid-runtime \
    pgbackrest \
    libdbd-pg-perl \
    libpq-dev
# /snippet:docker_install_packages

# snippet:docker_install_gomplate
RUN curl -L -o /usr/local/bin/gomplate https://github.com/hairyhenderson/gomplate/releases/download/${GOMPLATE_VERION}/gomplate_linux-amd64-slim && \
    echo "${GOMPLATE_CHECKSUM}" /usr/local/bin/gomplate | sha256sum -c && \
    chmod +x /usr/local/bin/gomplate
# /snippet:docker_install_gomplate

# snippet:docker_user
RUN groupadd --gid "${USER_GID}" "${USER}" && \
    useradd \
      --uid ${USER_ID} \
      --gid ${USER_GID} \
      --create-home \
      --home-dir /${USER} \
      --shell /bin/bash \
      ${USER}
# /snippet:docker_user

RUN mkdir -p ${DATA_DIR} && chown -R ${USER}:${USER} ${DATA_DIR} && chmod -R 700 ${DATA_DIR}
RUN mkdir -p ${BACKUP_DIR} && chown -R ${USER}:${USER} ${BACKUP_DIR}  && chmod -R 700 ${BACKUP_DIR}

COPY bin /rds/bin
RUN chmod -R 700 /rds && chown -R ${USER}:${USER} /rds

USER ${USER}
WORKDIR /rds

EXPOSE 5432

COPY templates /rds/templates

CMD /rds/bin/run.sh