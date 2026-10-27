# Clúster RabbitMQ de 2 nodos en AWS (EC2)

Mismo diseño que el clúster local de `../compose.yml`, desplegado en la nube con **Docker Compose**: cada instancia EC2
ejecuta [`compose.yml`](compose.yml) y las dos juntas forman un solo clúster.

```
        tu máquina ──── 5672 / 15672 (solo tu IP) ────┐
                                                     ▼
 ┌─ EC2 nodo 1 · us-east-2a · 172.31.0.10 ─┐   ┌─ EC2 nodo 2 · us-east-2b · 172.31.16.10 ─┐
 │  docker compose → rabbitmq:4.0-management│◄─►│  docker compose → rabbitmq:4.0-management │
 │  rabbit@ip-172-31-0-10                   │   │  rabbit@ip-172-31-16-10                   │
 └──────────────── epmd 4369 · distribución Erlang 25672 (solo entre los nodos) ────────────┘
```

## Archivos

| Archivo | Para qué sirve |
|---|---|
| [`compose.yml`](compose.yml) | Define el nodo RabbitMQ (imagen, red, volumen, healthcheck). Es el mismo en las dos instancias |
| `deploy-cluster.sh` | Crea la clave SSH, el security group y las 2 instancias, y luego ejecuta `apply-compose.sh` |
| `apply-compose.sh` | Copia `compose.yml` + la configuración de cada nodo a su instancia y ejecuta `docker compose up -d --wait` |
| `verify.sh` | Comprueba puertos, Management UI, contenedor sano y pertenencia al clúster |
| `destroy-cluster.sh` | Borra todo (las instancias cuestan mientras estén encendidas) |

```bash
./deploy-cluster.sh      # crear (o ./apply-compose.sh si las instancias ya existen y solo cambió el compose)
./verify.sh              # comprobar
./destroy-cluster.sh     # borrar
```

## Qué crea

| Recurso | Detalle |
|---|---|
| Región | `us-east-2`. El SCP de la organización niega EC2 en `us-east-1` y `us-west-2` |
| 2 instancias | Ubuntu 24.04, `t3.small`, en zonas de disponibilidad distintas, con IP privada fija |
| Nodo RabbitMQ | `rabbitmq:4.0-management` con `docker compose` (red host). El nombre del nodo sale del hostname: `rabbit@ip-172-31-0-10` y `rabbit@ip-172-31-16-10` |
| Formación del clúster | `classic_config` (`20-cluster.conf`): cada nodo conoce a los otros por nombre; el primero crea el clúster y el otro se une |
| Security group | 22, 5672 y 15672 solo desde la IP de quien despliega; entre los nodos, todo el tráfico |
| Secretos | `~/.campuslab-aws/` (clave SSH, usuario, contraseña y cookie de Erlang). **Fuera del repositorio** |

## Servicios y cómo acceder

Las direcciones públicas las muestra `deploy-cluster.sh` al terminar (también `aws ec2 describe-instances --region us-east-2`).
Cambian si las instancias se detienen y se vuelven a encender.

| Servicio | Dirección | Notas |
|---|---|---|
| AMQP (microservicios) | `<IP-nodo-1>:5672` y `<IP-nodo-2>:5672` | usuario y contraseña en `~/.campuslab-aws/rabbitmq.env` |
| Management UI | `http://<IP-nodo-1>:15672` y `http://<IP-nodo-2>:15672` | cada nodo muestra los dos; pestañas *Overview*, *Queues*, *Exchanges*, *Connections* |
| API HTTP de gestión | `http://<IP>:15672/api/...` | `/api/nodes`, `/api/queues`, `/api/overview` |
| SSH | `ssh -i ~/.campuslab-aws/campuslab-rabbitmq.pem ubuntu@<IP>` | solo desde la IP autorizada |
| Administración de colas por API | ver `ms-campuslab-mq-admin` (Swagger en `/swagger-ui.html`) | crear/borrar colas, exchanges y bindings |

Conectar un microservicio (la contraseña se llama `RABBITMQ_PASS` en notify y `RABBITMQ_PASSWORD` en bookings):

```bash
RABBITMQ_ADDRESSES=<IP-nodo-1>:5672,<IP-nodo-2>:5672 RABBITMQ_USER=... RABBITMQ_PASS=... java -jar ...
```

## Verificar que es un clúster

```bash
./verify.sh
ssh -i ~/.campuslab-aws/campuslab-rabbitmq.pem ubuntu@<IP-nodo-1> 'sudo docker exec rabbitmq rabbitmqctl cluster_status'
```

Deben aparecer los dos nodos en *Disk Nodes* y en *Running Nodes*, con la misma versión y sin *Network Partitions*.

## Alcance de la alta disponibilidad (probado)

| Situación | Resultado |
|---|---|
| Cae el **nodo 2** | El clúster sigue atendiendo en el nodo 1; al volver se reincorpora solo y sus consumidores se reconectan |
| Cae el **nodo 1** (colas `classic`) | Las colas viven en el nodo 1: quedan `down` y los mensajes publicados por el nodo 2 no se enrutan |
| Cae un nodo (colas `quorum` con 2 réplicas) | Sin mayoría (`minority`): la cola no atiende hasta que el nodo vuelve |

Una cola clásica vive en el nodo donde se declara, y RabbitMQ 4.0 ya no espeja colas clásicas. Una cola `quorum` replica entre
nodos pero necesita mayoría: con 2 nodos no tolera la caída de ninguno; para eso hacen falta 3.
El tipo se elige con `RABBITMQ_QUEUE_TYPE=classic|quorum` (igual en notify y bookings; cambiarlo exige borrar antes las colas).
