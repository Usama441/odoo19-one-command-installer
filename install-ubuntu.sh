#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this script as your normal sudo-enabled user, not as root."
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Unsupported system: Ubuntu 22.04 or 24.04 is required."
  exit 1
fi
. /etc/os-release
if [[ "${ID}" != "ubuntu" || ( "${VERSION_ID}" != "22.04" && "${VERSION_ID}" != "24.04" ) ]]; then
  echo "Unsupported system: detected ${PRETTY_NAME:-unknown}."
  exit 1
fi

read -r -p "Environment [testing/production] (testing): " DEPLOYMENT_MODE
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-testing}"
if [[ "$DEPLOYMENT_MODE" != "testing" && "$DEPLOYMENT_MODE" != "production" ]]; then
  echo "Please enter testing or production."
  exit 1
fi
read -r -p "Community port (8069): " COMMUNITY_PORT
COMMUNITY_PORT="${COMMUNITY_PORT:-8069}"
read -r -p "Enterprise port (8070): " ENTERPRISE_PORT
ENTERPRISE_PORT="${ENTERPRISE_PORT:-8070}"
valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}
if ! valid_port "$COMMUNITY_PORT" || ! valid_port "$ENTERPRISE_PORT"; then
  echo "Ports must be numbers from 1 to 65535."
  exit 1
fi
COMMUNITY_PORT="$((10#$COMMUNITY_PORT))"
ENTERPRISE_PORT="$((10#$ENTERPRISE_PORT))"
if [[ "$COMMUNITY_PORT" == "$ENTERPRISE_PORT" ]]; then
  echo "Community and Enterprise must use different ports."
  exit 1
fi

setup_docker_repository() {
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl openssl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker Engine and Compose plugin..."
  setup_docker_repository
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
fi

if systemctl cat docker.service >/dev/null 2>&1; then
  echo "Enabling Docker to start automatically at boot..."
  if ! sudo systemctl enable --now docker.service; then
    echo "Docker could not be enabled and started. Fix the Docker system service, then rerun this installer."
    exit 1
  fi
else
  echo "Warning: docker.service was not found, so automatic Docker startup could not be configured."
fi

DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
  if sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "Docker is installed, but its engine is not running. Start Docker and rerun this installer."
    exit 1
  fi
fi

if ! "${DOCKER[@]}" compose version >/dev/null 2>&1; then
  echo "Installing the Docker Compose plugin..."
  setup_docker_repository
  if ! sudo apt-get install -y docker-compose-plugin; then
    echo "Docker Compose could not be installed. Remove conflicting Docker packages, then install Docker Engine from Docker's official Ubuntu repository."
    exit 1
  fi
fi
if ! "${DOCKER[@]}" compose version >/dev/null 2>&1; then
  echo "Docker Compose is still unavailable. Log out and back in, then rerun this installer."
  exit 1
fi
COMPOSE_UP_HELP="$("${DOCKER[@]}" compose up --help 2>&1)"
if [[ "$COMPOSE_UP_HELP" != *"--wait-timeout"* ]]; then
  echo "This installer requires a newer Docker Compose plugin with --wait support. Update Docker Engine/Compose, then rerun it."
  exit 1
fi
COMMUNITY_DB_VOLUME_EXISTS="false"
ENTERPRISE_DB_VOLUME_EXISTS="false"
PGADMIN_VOLUME_EXISTS="false"
if "${DOCKER[@]}" volume inspect odoo19-dual_community-db >/dev/null 2>&1; then COMMUNITY_DB_VOLUME_EXISTS="true"; fi
if "${DOCKER[@]}" volume inspect odoo19-dual_enterprise-db >/dev/null 2>&1; then ENTERPRISE_DB_VOLUME_EXISTS="true"; fi
if "${DOCKER[@]}" volume inspect odoo19-dual_pgadmin-data >/dev/null 2>&1; then PGADMIN_VOLUME_EXISTS="true"; fi
if [[ ! -f .env &&
      ( "$COMMUNITY_DB_VOLUME_EXISTS" == "true" || "$ENTERPRISE_DB_VOLUME_EXISTS" == "true" || "$PGADMIN_VOLUME_EXISTS" == "true" ) ]]; then
  echo "Existing installer data volumes were found, but .env is missing. Restore .env from backup; generated replacement credentials would not unlock the existing data."
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Installing OpenSSL for secure password generation..."
  sudo apt-get update
  sudo apt-get install -y openssl
fi

mkdir -p config/community config/enterprise config/pgadmin addons/community addons/enterprise addons/enterprise-custom
read -r -p "Path to licensed Odoo 19 Enterprise addons (blank reuses existing addons, or starts Community only): " ENTERPRISE_SOURCE
START_ENTERPRISE="false"
if [[ -n "$ENTERPRISE_SOURCE" ]]; then
  if [[ ! -d "$ENTERPRISE_SOURCE" ]]; then
    echo "Enterprise addons directory was not found."
    exit 1
  fi
  if [[ "$(realpath "$ENTERPRISE_SOURCE")" != "$(realpath addons/enterprise)" ]]; then
    cp -a "$ENTERPRISE_SOURCE"/. addons/enterprise/
  fi
  START_ENTERPRISE="true"
elif find addons/enterprise -mindepth 1 ! -name .gitkeep -print -quit | grep -q .; then
  echo "Reusing the Enterprise addons already in addons/enterprise."
  START_ENTERPRISE="true"
fi

get_env_value() {
  local key="$1"
  awk -v key="$key" 'index($0, key "=") == 1 { value = substr($0, length(key) + 2); sub(/\r$/, "", value); print value; exit }' .env
}

get_config_value() {
  local path="$1" key="$2"
  [[ -f "$path" ]] || return 0
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$path"
}

ODOO_IMAGE="odoo:19.0-20260908"
POSTGRES_IMAGE="postgres:15.19"
PGADMIN_IMAGE="dpage/pgadmin4:9.17"
PGADMIN_ENABLED="false"
PGADMIN_PORT="5050"
PGADMIN_EMAIL="admin@example.com"
PGADMIN_CREDENTIALS_MISSING="false"
if [[ -f .env ]]; then
  COMMUNITY_DB_PASSWORD="$(get_env_value COMMUNITY_DB_PASSWORD)"
  ENTERPRISE_DB_PASSWORD="$(get_env_value ENTERPRISE_DB_PASSWORD)"
  if [[ -z "$COMMUNITY_DB_PASSWORD" || -z "$ENTERPRISE_DB_PASSWORD" ]]; then
    echo "The existing .env file is missing a database password. It was not overwritten because existing Docker volumes may still depend on it."
    exit 1
  fi
  COMMUNITY_ADMIN_PASSWORD="$(get_env_value COMMUNITY_ADMIN_PASSWORD)"
  ENTERPRISE_ADMIN_PASSWORD="$(get_env_value ENTERPRISE_ADMIN_PASSWORD)"
  COMMUNITY_ADMIN_PASSWORD="${COMMUNITY_ADMIN_PASSWORD:-$(get_config_value config/community/odoo.conf admin_passwd)}"
  ENTERPRISE_ADMIN_PASSWORD="${ENTERPRISE_ADMIN_PASSWORD:-$(get_config_value config/enterprise/odoo.conf admin_passwd)}"
  COMMUNITY_ADMIN_PASSWORD="${COMMUNITY_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  ENTERPRISE_ADMIN_PASSWORD="${ENTERPRISE_ADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  ODOO_IMAGE="$(get_env_value ODOO_IMAGE)"
  POSTGRES_IMAGE="$(get_env_value POSTGRES_IMAGE)"
  ODOO_IMAGE="${ODOO_IMAGE:-odoo:19.0-20260908}"
  POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15.19}"
  SAVED_PGADMIN_IMAGE="$(get_env_value PGADMIN_IMAGE)"
  SAVED_PGADMIN_ENABLED="$(get_env_value PGADMIN_ENABLED)"
  SAVED_PGADMIN_PORT="$(get_env_value PGADMIN_PORT)"
  SAVED_PGADMIN_EMAIL="$(get_env_value PGADMIN_EMAIL)"
  SAVED_PGADMIN_PASSWORD="$(get_env_value PGADMIN_PASSWORD)"
  PGADMIN_IMAGE="${SAVED_PGADMIN_IMAGE:-$PGADMIN_IMAGE}"
  if [[ "$SAVED_PGADMIN_ENABLED" == "true" ]]; then PGADMIN_ENABLED="true"; fi
  PGADMIN_PORT="${SAVED_PGADMIN_PORT:-$PGADMIN_PORT}"
  PGADMIN_EMAIL="${SAVED_PGADMIN_EMAIL:-$PGADMIN_EMAIL}"
  if [[ "$PGADMIN_VOLUME_EXISTS" == "true" &&
        ( -z "$SAVED_PGADMIN_EMAIL" || -z "$SAVED_PGADMIN_PASSWORD" ) ]]; then
    PGADMIN_CREDENTIALS_MISSING="true"
  fi
  PGADMIN_PASSWORD="${SAVED_PGADMIN_PASSWORD:-$(openssl rand -hex 24)}"
  echo "Existing installation detected; database and Odoo master passwords will be reused."
else
  COMMUNITY_DB_PASSWORD="$(openssl rand -hex 24)"
  ENTERPRISE_DB_PASSWORD="$(openssl rand -hex 24)"
  COMMUNITY_ADMIN_PASSWORD="$(openssl rand -hex 24)"
  ENTERPRISE_ADMIN_PASSWORD="$(openssl rand -hex 24)"
  PGADMIN_PASSWORD="$(openssl rand -hex 24)"
fi

if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  read -r -p "Install/update and configure pgAdmin? [Y/n]: " PGADMIN_CHOICE
  PGADMIN_CHOICE="${PGADMIN_CHOICE:-y}"
else
  read -r -p "Install/update and configure pgAdmin? [y/N]: " PGADMIN_CHOICE
  PGADMIN_CHOICE="${PGADMIN_CHOICE:-n}"
fi
case "${PGADMIN_CHOICE,,}" in
  y|yes) PGADMIN_ENABLED="true" ;;
  n|no) PGADMIN_ENABLED="false" ;;
  *) echo "Please enter y or n."; exit 1 ;;
esac

if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  if [[ "$PGADMIN_CREDENTIALS_MISSING" == "true" ]]; then
    echo "The existing pgAdmin data volume was found, but its saved login credentials are missing from .env. Restore .env from backup before enabling pgAdmin."
    exit 1
  fi
  read -r -p "pgAdmin port ($PGADMIN_PORT): " PGADMIN_PORT_INPUT
  PGADMIN_PORT="${PGADMIN_PORT_INPUT:-$PGADMIN_PORT}"
  if ! valid_port "$PGADMIN_PORT"; then
    echo "The pgAdmin port must be a number from 1 to 65535."
    exit 1
  fi
  PGADMIN_PORT="$((10#$PGADMIN_PORT))"
  if [[ "$PGADMIN_PORT" == "$COMMUNITY_PORT" || "$PGADMIN_PORT" == "$ENTERPRISE_PORT" ]]; then
    echo "The pgAdmin port must be different from both Odoo ports."
    exit 1
  fi
  if [[ "$PGADMIN_VOLUME_EXISTS" == "true" ]]; then
    echo "Reusing existing pgAdmin login email: $PGADMIN_EMAIL"
  else
    read -r -p "pgAdmin login email ($PGADMIN_EMAIL): " PGADMIN_EMAIL_INPUT
    PGADMIN_EMAIL="${PGADMIN_EMAIL_INPUT:-$PGADMIN_EMAIL}"
  fi
  if [[ ! "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    echo "Enter a valid pgAdmin login email address."
    exit 1
  fi
fi

if ! valid_port "$PGADMIN_PORT"; then PGADMIN_PORT="5050"; fi
if [[ ! "$PGADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then PGADMIN_EMAIL="admin@example.com"; fi
if [[ ! "$ODOO_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ||
      ! "$POSTGRES_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ||
      ! "$PGADMIN_IMAGE" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]+$ ]]; then
  echo "An image reference in .env is invalid."
  exit 1
fi

umask 077
cat > .env <<EOF
ODOO_IMAGE=$ODOO_IMAGE
POSTGRES_IMAGE=$POSTGRES_IMAGE
PGADMIN_IMAGE=$PGADMIN_IMAGE
COMMUNITY_PORT=$COMMUNITY_PORT
ENTERPRISE_PORT=$ENTERPRISE_PORT
COMMUNITY_DB_PASSWORD=$COMMUNITY_DB_PASSWORD
ENTERPRISE_DB_PASSWORD=$ENTERPRISE_DB_PASSWORD
COMMUNITY_ADMIN_PASSWORD=$COMMUNITY_ADMIN_PASSWORD
ENTERPRISE_ADMIN_PASSWORD=$ENTERPRISE_ADMIN_PASSWORD
PGADMIN_ENABLED=$PGADMIN_ENABLED
PGADMIN_PORT=$PGADMIN_PORT
PGADMIN_EMAIL=$PGADMIN_EMAIL
PGADMIN_PASSWORD=$PGADMIN_PASSWORD
EOF

WORKERS="0"
LIMIT_MEMORY_HARD="0"
LIMIT_MEMORY_SOFT="0"
if [[ "$DEPLOYMENT_MODE" == "production" ]]; then
  WORKERS="2"
  LIMIT_MEMORY_HARD="2684354560"
  LIMIT_MEMORY_SOFT="2147483648"
fi

write_config() {
  local target="$1" db_host="$2" db_password="$3" admin_password="$4" addons_path="$5"
  cat > "$target" <<EOF
[options]
admin_passwd = $admin_password
db_host = $db_host
db_port = 5432
db_user = odoo
db_password = $db_password
addons_path = $addons_path
data_dir = /var/lib/odoo
list_db = True
proxy_mode = False
workers = $WORKERS
max_cron_threads = 1
limit_memory_hard = $LIMIT_MEMORY_HARD
limit_memory_soft = $LIMIT_MEMORY_SOFT
EOF
}
write_config config/community/odoo.conf db-community "$COMMUNITY_DB_PASSWORD" "$COMMUNITY_ADMIN_PASSWORD" "/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons"
write_config config/enterprise/odoo.conf db-enterprise "$ENTERPRISE_DB_PASSWORD" "$ENTERPRISE_ADMIN_PASSWORD" "/mnt/enterprise-addons,/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons"

if [[ "$START_ENTERPRISE" == "true" ]]; then
  cat > config/pgadmin/servers.json <<'EOF'
{
  "Servers": {
    "1": {
      "Name": "Odoo 19 Community PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-community",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    },
    "2": {
      "Name": "Odoo 19 Enterprise PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-enterprise",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
else
  cat > config/pgadmin/servers.json <<'EOF'
{
  "Servers": {
    "1": {
      "Name": "Odoo 19 Community PostgreSQL",
      "Group": "Odoo 19",
      "Host": "db-community",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "odoo",
      "SSLMode": "prefer"
    }
  }
}
EOF
fi
cat > config/pgadmin/pgpass <<EOF
db-community:5432:*:odoo:$COMMUNITY_DB_PASSWORD
db-enterprise:5432:*:odoo:$ENTERPRISE_DB_PASSWORD
EOF
chmod 600 .env config/community/odoo.conf config/enterprise/odoo.conf config/pgadmin/servers.json config/pgadmin/pgpass

COMPOSE_PROFILE=()
if [[ "$PGADMIN_ENABLED" == "true" ]]; then COMPOSE_PROFILE=(--profile pgadmin); fi
"${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" pull

# Keep the configuration private from other host users while making it readable
# by the non-root odoo user in the official container image.
ODOO_CONTAINER_GID="$("${DOCKER[@]}" run --rm --entrypoint id "$ODOO_IMAGE" -g)"
if [[ "$ODOO_CONTAINER_GID" =~ ^[0-9]+$ ]]; then
  sudo chgrp "$ODOO_CONTAINER_GID" config/community/odoo.conf config/enterprise/odoo.conf
  chmod 640 config/community/odoo.conf config/enterprise/odoo.conf
fi
if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
    -v "$SCRIPT_DIR/config/community/odoo.conf:/tmp/odoo.conf:ro" \
    "$ODOO_IMAGE" -c 'test -r /tmp/odoo.conf'; then
  echo "Warning: using mode 644 for Odoo configuration because this Docker setup remaps container users."
  chmod 644 config/community/odoo.conf config/enterprise/odoo.conf
fi

if [[ "$PGADMIN_ENABLED" == "true" ]]; then
  if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
      -v "$SCRIPT_DIR/config/pgadmin/pgpass:/tmp/pgpass:ro" \
      "$PGADMIN_IMAGE" -c 'test -r /tmp/pgpass'; then
    PGADMIN_CONTAINER_GID="$("${DOCKER[@]}" run --rm --entrypoint id "$PGADMIN_IMAGE" -g)"
    if [[ ! "$PGADMIN_CONTAINER_GID" =~ ^[0-9]+$ ]]; then
      echo "Could not determine the pgAdmin container group."
      exit 1
    fi
    sudo chgrp "$PGADMIN_CONTAINER_GID" config/pgadmin/servers.json config/pgadmin/pgpass
    chmod 640 config/pgadmin/servers.json config/pgadmin/pgpass
    if ! "${DOCKER[@]}" run --rm --entrypoint /bin/sh \
        -v "$SCRIPT_DIR/config/pgadmin/pgpass:/tmp/pgpass:ro" \
        "$PGADMIN_IMAGE" -c 'test -r /tmp/pgpass'; then
      echo "pgAdmin cannot securely read its generated password file on this Docker setup."
      exit 1
    fi
  fi
fi

if [[ "$START_ENTERPRISE" == "true" ]]; then
  "${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" up -d --wait --wait-timeout 300
else
  START_SERVICES=(db-community community)
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then START_SERVICES+=(pgadmin); fi
  "${DOCKER[@]}" compose "${COMPOSE_PROFILE[@]}" up -d --wait --wait-timeout 300 "${START_SERVICES[@]}"
fi
if [[ "$PGADMIN_ENABLED" != "true" ]] &&
   [[ -n "$("${DOCKER[@]}" compose --profile pgadmin ps -q pgadmin)" ]]; then
  "${DOCKER[@]}" compose --profile pgadmin stop pgadmin
fi

if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q '^Status: active'; then
  sudo ufw allow "${COMMUNITY_PORT}/tcp"
  if [[ "$START_ENTERPRISE" == "true" ]]; then
    sudo ufw allow "${ENTERPRISE_PORT}/tcp"
  fi
  if [[ "$PGADMIN_ENABLED" == "true" ]]; then
    sudo ufw allow "${PGADMIN_PORT}/tcp"
  fi
fi

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
HOST_IP="${HOST_IP:-127.0.0.1}"
{
cat <<EOF
Mode: $DEPLOYMENT_MODE
Automatic startup: enabled (Docker at boot; containers restart unless manually stopped)
Community: http://$HOST_IP:$COMMUNITY_PORT
Community Odoo master password: $COMMUNITY_ADMIN_PASSWORD
EOF
if [[ "$START_ENTERPRISE" == "true" ]]; then
cat <<EOF
Enterprise: http://$HOST_IP:$ENTERPRISE_PORT
Enterprise Odoo master password: $ENTERPRISE_ADMIN_PASSWORD
EOF
else
  echo "Enterprise: not started"
fi
if [[ "$PGADMIN_ENABLED" == "true" ]]; then
cat <<EOF
pgAdmin: http://$HOST_IP:$PGADMIN_PORT
pgAdmin login email: $PGADMIN_EMAIL
pgAdmin login password: $PGADMIN_PASSWORD
EOF
else
  echo "pgAdmin: not started"
fi
cat <<EOF
Odoo image: $ODOO_IMAGE
PostgreSQL image: $POSTGRES_IMAGE
EOF
if [[ "$PGADMIN_ENABLED" == "true" ]]; then echo "pgAdmin image: $PGADMIN_IMAGE"; fi
} > installation-info.txt
chmod 600 .env installation-info.txt

echo
cat installation-info.txt
echo "Credentials are stored in $SCRIPT_DIR/installation-info.txt (owner-readable only)."
