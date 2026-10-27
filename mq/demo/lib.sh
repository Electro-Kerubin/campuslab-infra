#!/usr/bin/env bash
# Funciones comunes del kit de demostración. Se usa con `source lib.sh` desde los otros scripts.
#
# Deja definidas: RMQ_N1 / RMQ_N2 (IP pública de cada nodo), RABBITMQ_USER / RABBITMQ_PASS, ROOT (carpeta con los
# microservicios) y LOGS (carpeta de logs). Las credenciales vienen de ~/.campuslab-aws/rabbitmq.env, fuera del repositorio.

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${ROOT:-$(cd "$DEMO_DIR/../../.." && pwd)}"           # carpeta que contiene ms-campuslab-* y campuslab-infra
SECRETS_DIR="${SECRETS_DIR:-$HOME/.campuslab-aws}"
LOGS="$SECRETS_DIR/demo-logs"
REGION="${REGION:-us-east-2}"
mkdir -p "$LOGS"

[ -f "$SECRETS_DIR/rabbitmq.env" ] || { echo "Falta $SECRETS_DIR/rabbitmq.env (lo crea mq/aws/deploy-cluster.sh)"; exit 1; }
# shellcheck disable=SC1091
source "$SECRETS_DIR/rabbitmq.env"
export RABBITMQ_USER RABBITMQ_PASS

node_ip() {
  aws --region "$REGION" ec2 describe-instances --filters "Name=tag:Name,Values=campuslab-rabbitmq-$1" \
    "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text | tr -d '\r'
}
RMQ_N1="${RMQ_N1:-$(node_ip 1)}"
RMQ_N2="${RMQ_N2:-$(node_ip 2)}"
if [ -z "$RMQ_N1" ] || [ "$RMQ_N1" = "None" ]; then echo "No encuentro el nodo 1 en AWS (¿está encendido? ¿aws configure?)"; exit 1; fi
export RMQ_N1 RMQ_N2
export RMQ_ADDRESSES="$RMQ_N1:5672,$RMQ_N2:5672"

# Libera un puerto local matando al proceso que lo escucha (Git Bash en Windows)
kill_port() {
  local pid
  pid="$(netstat -ano | grep ":$1 " | grep LISTEN | awk '{print $5}' | head -1 || true)"
  [ -n "$pid" ] && taskkill //PID "$pid" //F >/dev/null 2>&1 && echo "  detenido el proceso del puerto $1"
  return 0
}

# Espera a que un puerto local responda HTTP (cualquier código distinto de 000)
wait_http() {
  for _ in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$1")" != "000" ] && return 0
    sleep 2
  done
  return 1
}

# node (Windows) no entiende rutas /c/... de Git Bash: ruta con formato C:/... para los scripts .js
win_path() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || echo "$1"; }
