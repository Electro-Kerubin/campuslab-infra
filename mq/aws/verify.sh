#!/usr/bin/env bash
# Comprueba que el clúster RabbitMQ de AWS está accesible y funcionando: puertos, Management UI, pertenencia al
# clúster y contenedor compose sano en cada instancia. Sale con código 1 si algo falla.
#
#   ./verify.sh
set -uo pipefail
export MSYS_NO_PATHCONV=1

REGION="${REGION:-us-east-2}"
PROJECT="campuslab-rabbitmq"
SECRETS_DIR="${SECRETS_DIR:-$HOME/.campuslab-aws}"
KEY_FILE="$SECRETS_DIR/$PROJECT.pem"
# shellcheck disable=SC1090
source "$SECRETS_DIR/rabbitmq.env"
SSH_OPTS=(-i "$KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)

fail=0
ok()  { echo "  OK    $1"; }
bad() { echo "  FALLA $1"; fail=1; }
pub_ip() { aws --region "$REGION" ec2 describe-instances --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text | tr -d '\r'; }
tcp_open() { (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null; }

IPS=()
for n in 1 2; do
  ip="$(pub_ip "$PROJECT-$n")"
  echo "Nodo $n ($ip)"
  IPS+=("$ip")
  if [ -z "$ip" ] || [ "$ip" = "None" ]; then bad "la instancia no está en ejecución"; continue; fi

  tcp_open "$ip" 5672  && ok "AMQP 5672 accesible"            || bad "AMQP 5672 no responde"
  code="$(curl -s -o /dev/null -m 8 -w '%{http_code}' "http://$ip:15672/")"
  [ "$code" = "200" ] && ok "Management UI http://$ip:15672 (HTTP 200)" || bad "Management UI responde HTTP $code"

  state="$(ssh "${SSH_OPTS[@]}" "ubuntu@$ip" "sudo docker inspect -f '{{index .Config.Labels \"com.docker.compose.project\"}}/{{.State.Health.Status}}' rabbitmq" 2>/dev/null)"
  [ "$state" = "campuslab-mq/healthy" ] && ok "contenedor de docker compose sano ($state)" || bad "contenedor compose: ${state:-no encontrado}"
done

echo "Clúster"
for ip in "${IPS[@]}"; do
  [ -z "$ip" ] || [ "$ip" = "None" ] && continue
  json="$(curl -s -m 10 -u "$RABBITMQ_USER:$RABBITMQ_PASS" "http://$ip:15672/api/nodes")"
  running="$(echo "$json" | grep -o '"running":true' | wc -l)"
  [ "$running" -ge 2 ] && ok "visto desde $ip: $running nodos en ejecución" || bad "visto desde $ip: solo $running nodos en ejecución"
  echo "$json" | grep -q '"partitions":\[[^]]' && bad "hay particiones de red desde $ip" || ok "sin particiones de red desde $ip"
done

echo; [ "$fail" -eq 0 ] && echo "RESULTADO: todo correcto" || echo "RESULTADO: hay fallas"
exit "$fail"
