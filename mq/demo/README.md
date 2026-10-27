# Kit de demostración de RabbitMQ (AWS)

Scripts para mostrar el sistema funcionando contra el clúster de AWS (`../aws/`) sin depender de Azure ni de levantar toda la plataforma.
Se ejecutan desde Git Bash, dentro de esta carpeta. Las credenciales se leen de `~/.campuslab-aws/` (fuera del repositorio).

| Script | Qué hace |
|---|---|
| `urls.sh` | Muestra las URLs de la Management UI de los dos nodos, Swagger y los logs |
| `start-mq-admin.sh` | Levanta `ms-campuslab-mq-admin` (puerto 8085) contra AWS y un emisor de tokens local. Swagger en `/swagger-ui.html` |
| `token.sh` | Imprime y copia al portapapeles el token ADMIN de demostración (`./token.sh tecnico` da uno sin permisos) |
| `start-notify.sh` | Levanta `ms-campuslab-notify` (puerto 8084) contra AWS. `NOTIFY_SIMULATED_FAILURE_RATE=1.0 ./start-notify.sh` hace fallar cada intento |
| `send.sh <tipo>` | Publica un mensaje de ejemplo: `email`, `prep`, `voucher-retiro`, `voucher-devolucion`, `email-invalido`, `prep-invalido`, `voucher-invalido`, `ilegible`. Con `--duplicado` lo envía dos veces con el mismo `eventId` |
| `run-demo-endpoints.sh` | 45 comprobaciones de la API del administrador: exchanges direct y topic, colas, bindings, enrutamiento y borrado |
| `run-demo-validacion.sh` | 37 comprobaciones de validación: peticiones inválidas que deben responder 400/415/422 sin tocar el broker |
| `limpiar-dlq.sh` | Vacía las tres DLQ para empezar de cero |
| `nodo.sh <1\|2> '<comando>'` | Ejecuta un comando por SSH en un nodo (por ejemplo `rabbitmqctl cluster_status`) |
| `stop-demo.sh` | Detiene notify, mq-admin y el emisor de tokens (no toca AWS) |

## Cómo funciona la autenticación de la demo
En producción `mq-admin` valida los JWT de Azure AD. Aquí `auth-local.js` firma tokens de prueba con una clave propia y `mq-admin` arranca con
`SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_JWK_SET_URI` apuntando a ella. Es el mismo código de validación y el mismo control de roles
(`ADMIN` pasa, `TECNICO` recibe 403); solo cambia de dónde sale la clave pública. Los tokens duran 4 horas.

Los scripts de arranque compilan el servicio si falta su jar. Compílalos antes de la presentación para no esperar.
