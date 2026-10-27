#!/usr/bin/env bash
# Levanta ms-campuslab-mq-admin (puerto 8085) conectado al clúster de AWS, con el emisor de tokens de demostración.
#
#   ./start-mq-admin.sh     ->  Swagger: http://localhost:8085/swagger-ui.html   (token: node auth-local.js --print admin)
#
# En producción valida los JWT de Azure AD; aquí usa las claves del emisor local para no depender de un usuario ADMIN de Azure.
# Se conecta primero al nodo 2 (notify va al nodo 1): así la pestaña Connections muestra conexiones en los dos nodos.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

JAR="$ROOT/ms-campuslab-mq-admin/target/ms-campuslab-mq-admin-1.0-SNAPSHOT.jar"
[ -f "$JAR" ] || { echo "Compilando mq-admin..."; (cd "$ROOT/ms-campuslab-mq-admin" && mvn -q -DskipTests package); }

kill_port 18999; kill_port 8085
(cd "$DEMO_DIR" && nohup node auth-local.js > "$LOGS/auth-local.log" 2>&1 &) >/dev/null 2>&1
sleep 2

(cd "$ROOT/ms-campuslab-mq-admin" && \
  SERVER_PORT=8085 TENANT_ID=demo \
  SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI=http://127.0.0.1:18999/jwks \
  SPRING_RABBITMQ_ADDRESSES="$RMQ_N2:5672,$RMQ_N1:5672" \
  nohup java -jar "$(win_path "$JAR")" > "$LOGS/mq-admin.log" 2>&1 &) >/dev/null 2>&1

echo "Esperando a mq-admin..."
wait_http "http://localhost:8085/v3/api-docs" || { echo "mq-admin no arrancó; mira $LOGS/mq-admin.log"; exit 1; }
echo "mq-admin listo."
echo "  Swagger : http://localhost:8085/swagger-ui.html"
echo "  Token   : node \"$(win_path "$DEMO_DIR/auth-local.js")\" --print admin"
echo "  Log     : tail -f \"$LOGS/mq-admin.log\""
