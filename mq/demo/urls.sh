#!/usr/bin/env bash
# Muestra las direcciones de la demostración (la contraseña no se imprime: está en ~/.campuslab-aws/rabbitmq.env).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
echo "RabbitMQ Management UI (usuario: $RABBITMQ_USER)"
echo "  Nodo 1 : http://$RMQ_N1:15672"
echo "  Nodo 2 : http://$RMQ_N2:15672"
echo "AMQP     : $RMQ_N1:5672 , $RMQ_N2:5672"
echo "mq-admin : http://localhost:8085/swagger-ui.html   (./start-mq-admin.sh; token con ./token.sh)"
echo "notify   : http://localhost:8084/api/notify/dlq    (requiere ./start-notify.sh)"
echo "Logs     : $LOGS"
