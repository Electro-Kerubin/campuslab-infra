#!/usr/bin/env bash
# Ejecuta un comando en uno de los nodos de AWS por SSH.
#   ./nodo.sh 1 'sudo docker exec rabbitmq rabbitmqctl cluster_status'
#   ./nodo.sh 2 'sudo docker compose -f /opt/rabbitmq/compose.yml ps'
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
N="$1"; shift
IP="$RMQ_N1"; [ "$N" = "2" ] && IP="$RMQ_N2"
ssh -i "$SECRETS_DIR/campuslab-rabbitmq.pem" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "ubuntu@$IP" "$@"
