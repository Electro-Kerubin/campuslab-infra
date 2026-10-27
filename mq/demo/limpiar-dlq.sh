#!/usr/bin/env bash
# Vacía las tres DLQ del clúster de AWS (para empezar una demostración desde cero). No toca las colas principales.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for q in q.cmd.email.dlq q.cmd.prep.dlq q.cmd.voucher.dlq; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -u "$RABBITMQ_USER:$RABBITMQ_PASS" -X DELETE "http://$RMQ_N1:15672/api/queues/%2F/$q/contents")"
  echo "  $q -> $([ "$code" = "204" ] && echo vaciada || echo "HTTP $code (¿aún no existe? se crea al arrancar notify)")"
done
