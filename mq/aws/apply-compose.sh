#!/usr/bin/env bash
# Copia compose.yml y la configuración de cada nodo a su instancia EC2 y ejecuta `docker compose up -d --wait`.
#
#   ./apply-compose.sh            # aplica el compose a los 2 nodos (de a uno: el clúster se mantiene)
#
# Se usa tanto al crear el clúster (lo invoca deploy-cluster.sh) como para actualizar uno que ya existe.
# Si el nodo venía de un `docker run` anterior, ese contenedor se reemplaza por el del compose conservando
# el volumen, así que el nodo mantiene su estado y se reincorpora solo al clúster.
set -euo pipefail
export MSYS_NO_PATHCONV=1

REGION="${REGION:-us-east-2}"
PROJECT="campuslab-rabbitmq"
SECRETS_DIR="${SECRETS_DIR:-$HOME/.campuslab-aws}"
KEY_FILE="$SECRETS_DIR/$PROJECT.pem"
ENV_FILE="$SECRETS_DIR/rabbitmq.env"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IP1="${IP1:-172.31.0.10}"; IP2="${IP2:-172.31.16.10}"
HOST1="ip-${IP1//./-}"; HOST2="ip-${IP2//./-}"

# shellcheck disable=SC1090
source "$ENV_FILE"
SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15)

pub_ip() { aws --region "$REGION" ec2 describe-instances --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text | tr -d '\r'; }

STAGE="$(mktemp -d "$SECRETS_DIR/stage.XXXXXX")"   # con secretos: dentro de ~/.campuslab-aws, nunca en el repo
trap 'rm -rf "$STAGE"' EXIT

# .env (secretos) y 20-cluster.conf (los dos nombres de nodo) son iguales en ambas instancias
cat > "$STAGE/.env" <<EOF
RABBITMQ_USER=$RABBITMQ_USER
RABBITMQ_PASS=$RABBITMQ_PASS
RABBITMQ_ERLANG_COOKIE=$RABBITMQ_ERLANG_COOKIE
EOF
cat > "$STAGE/20-cluster.conf" <<EOF
# Cada nodo conoce a los otros por nombre; el primero crea el clúster y los demás se le unen.
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@$HOST1
cluster_formation.classic_config.nodes.2 = rabbit@$HOST2
EOF
cp "$HERE/compose.yml" "$STAGE/compose.yml"

apply_node() { # nombre-instancia
  local ip; ip="$(pub_ip "$1")"
  echo "== $1 ($ip)"
  # La instancia puede estar terminando de arrancar (cloud-init): esperar a que Docker esté listo
  for _ in $(seq 1 60); do
    ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'cloud-init status --wait >/dev/null 2>&1; command -v docker >/dev/null' 2>/dev/null && break
    sleep 5
  done
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'sudo mkdir -p /opt/rabbitmq && sudo chown -R ubuntu: /opt/rabbitmq'
  scp "${SSH_OPTS[@]}" -q "$STAGE/compose.yml" "$STAGE/.env" "$STAGE/20-cluster.conf" "ubuntu@$ip:/opt/rabbitmq/"
  ssh "${SSH_OPTS[@]}" "ubuntu@$ip" 'chmod 600 /opt/rabbitmq/.env; bash -s' <<'REMOTE'
set -euo pipefail
cd /opt/rabbitmq
# Las instancias creadas antes no tienen a ubuntu en el grupo docker: siempre con sudo
docker() { sudo docker "$@"; }
docker compose version >/dev/null 2>&1 || { sudo apt-get update -y -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose-v2; }
# Contenedor creado por un `docker run` anterior (no por compose): se reemplaza; el volumen rabbitmq_data se conserva
if docker inspect rabbitmq >/dev/null 2>&1 && [ -z "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' rabbitmq)" ]; then
  echo "reemplazando el contenedor creado con docker run"
  docker rm -f rabbitmq >/dev/null
fi
docker compose up -d --wait --wait-timeout 240
docker compose ps
REMOTE
}

# De a un nodo (el nodo 1 primero: es el que crea el clúster cuando se despliega de cero); mientras uno
# se reinicia, el otro mantiene el clúster
apply_node "$PROJECT-1"
apply_node "$PROJECT-2"
echo "Listo: compose aplicado en los 2 nodos."
