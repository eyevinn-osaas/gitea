#!/bin/bash
set -e

# OSC-specific environment variable mappings

# Map PORT to HTTP_PORT for Gitea configuration
export HTTP_PORT="${PORT:-3000}"

# Map OSC_HOSTNAME to DOMAIN and ROOT_URL if set
if [ -n "$OSC_HOSTNAME" ]; then
    export DOMAIN="${DOMAIN:-$OSC_HOSTNAME}"
    export ROOT_URL="${ROOT_URL:-https://$OSC_HOSTNAME/}"
fi

# Parse DATABASE_URL if set (format: postgres://user:pass@host:port/dbname or mysql://user:pass@host:port/dbname)
if [ -n "$DATABASE_URL" ]; then
    # Extract the protocol/db type
    proto="${DATABASE_URL%%://*}"
    case "$proto" in
        postgres|postgresql)
            export DB_TYPE="${DB_TYPE:-postgres}"
            ;;
        mysql)
            export DB_TYPE="${DB_TYPE:-mysql}"
            ;;
        sqlite|sqlite3)
            export DB_TYPE="${DB_TYPE:-sqlite3}"
            ;;
        *)
            echo "Warning: Unknown database type in DATABASE_URL: $proto"
            ;;
    esac

    # Remove protocol prefix
    url_without_proto="${DATABASE_URL#*://}"

    # Check if there are credentials (contains @)
    if [[ "$url_without_proto" == *"@"* ]]; then
        # Extract credentials part (before @)
        credentials="${url_without_proto%%@*}"
        # Extract host and path part (after @)
        host_and_path="${url_without_proto#*@}"

        # Split credentials into user and password
        if [[ "$credentials" == *":"* ]]; then
            export DB_USER="${DB_USER:-${credentials%%:*}}"
            export DB_PASSWD="${DB_PASSWD:-${credentials#*:}}"
        else
            export DB_USER="${DB_USER:-$credentials}"
        fi
    else
        host_and_path="$url_without_proto"
    fi

    # Extract database name (after /)
    if [[ "$host_and_path" == *"/"* ]]; then
        host_and_port="${host_and_path%%/*}"
        db_name_and_params="${host_and_path#*/}"
        # Remove query parameters if present
        db_name="${db_name_and_params%%\?*}"
        export DB_NAME="${DB_NAME:-$db_name}"
    else
        host_and_port="$host_and_path"
    fi

    # Set DB_HOST (includes port if specified)
    export DB_HOST="${DB_HOST:-$host_and_port}"
fi

# Create data directories if they don't exist (needed when volume is mounted)
mkdir -p /data/gitea/conf /data/gitea/log /data/git
chown -R ${USER}:git /data/gitea /data/git 2>/dev/null || true

# Create config if it doesn't exist
if [ ! -f ${GITEA_CUSTOM}/conf/app.ini ]; then
    mkdir -p ${GITEA_CUSTOM}/conf

    # Set INSTALL_LOCK to true only if SECRET_KEY is not empty and INSTALL_LOCK is empty
    if [ -n "$SECRET_KEY" ] && [ -z "$INSTALL_LOCK" ]; then
        INSTALL_LOCK=true
    fi

    # Substitute the environment variables in the template
    APP_NAME=${APP_NAME:-"Gitea: Git with a cup of tea"} \
    RUN_MODE=${RUN_MODE:-"prod"} \
    DOMAIN=${DOMAIN:-"localhost"} \
    SSH_DOMAIN=${SSH_DOMAIN:-"localhost"} \
    HTTP_PORT=${HTTP_PORT} \
    ROOT_URL=${ROOT_URL:-""} \
    DISABLE_SSH=${DISABLE_SSH:-"true"} \
    SSH_PORT=${SSH_PORT:-"22"} \
    SSH_LISTEN_PORT=${SSH_LISTEN_PORT:-"${SSH_PORT}"} \
    LFS_START_SERVER=${LFS_START_SERVER:-"false"} \
    DB_TYPE=${DB_TYPE:-"sqlite3"} \
    DB_HOST=${DB_HOST:-"localhost:3306"} \
    DB_NAME=${DB_NAME:-"gitea"} \
    DB_USER=${DB_USER:-"root"} \
    DB_PASSWD=${DB_PASSWD:-""} \
    INSTALL_LOCK=${INSTALL_LOCK:-"false"} \
    DISABLE_REGISTRATION=${DISABLE_REGISTRATION:-"false"} \
    REQUIRE_SIGNIN_VIEW=${REQUIRE_SIGNIN_VIEW:-"false"} \
    SECRET_KEY=${SECRET_KEY:-""} \
    envsubst < /etc/templates/app.ini > ${GITEA_CUSTOM}/conf/app.ini

    chown ${USER}:git ${GITEA_CUSTOM}/conf/app.ini
fi

# Replace app.ini settings with env variables in the form GITEA__SECTION_NAME__KEY_NAME
/app/gitea/gitea config edit-ini --in-place --apply-env --config ${GITEA_CUSTOM}/conf/app.ini

# Ensure correct ownership
chown -R ${USER}:git /data/gitea /app/gitea /data/git 2>/dev/null || true
chmod 0755 /data/gitea /app/gitea /data/git

# Run gitea as git user
cd /app/gitea
exec su-exec ${USER} /app/gitea/gitea web
