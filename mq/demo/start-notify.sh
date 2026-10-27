#!/usr/bin/env bash
# Levanta ms-campuslab-notify (puerto 8084) conectado a los dos nodos del clúster de AWS.
#
#   ./start-notify.sh                       # normal
#   NOTIFY_SIMULATED_FAILURE_RATE=1.0 ./start-notify.sh    # cada intento falla: se ven los 3 reintentos y la DLQ
#
# El monitor de DLQ revisa cada 10 s (en producción, 30 s) para que se vea rápido en la demostración.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

JAR="$ROOT/ms-campuslab-notify/target/ms-campuslab-notify-1.0-SNAPSHOT.jar"
[ -f "$JAR" ] || { echo "Compilando notify..."; (cd "$ROOT/ms-campuslab-notify" && mvn -q -DskipTests package); }

kill_port 8084

(cd "$ROOT/ms-campuslab-notify" && \
  SERVER_PORT=8084 \
  RABBITMQ_ADDRESSES="$RMQ_ADDRESSES" RABBITMQ_USER="$RABBITMQ_USER" RABBITMQ_PASS="$RABBITMQ_PASS" \
  CAMPUSLAB_NOTIFY_DLQ_MONITOR_INITIAL_DELAY_MS=3000 CAMPUSLAB_NOTIFY_DLQ_MONITOR_INTERVAL_MS=10000 \
  NOTIFY_SIMULATED_FAILURE_RATE="${NOTIFY_SIMULATED_FAILURE_RATE:-0}" \
  nohup java -jar "$(win_path "$JAR")" > "$LOGS/notify.log" 2>&1 &) >/dev/null 2>&1

echo "Esperando a notify..."
wait_http "http://localhost:8084/api/notify/dlq" || { echo "notify no arrancó; mira $LOGS/notify.log"; exit 1; }
echo "notify listo (3 consumidores conectados al clúster)."
echo "  Log : tail -f \"$LOGS/notify.log\""
