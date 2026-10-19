# 🏗️ CampusLab - Infra

Repositorio de infraestructura compartida del proyecto **CampusLab**. Aquí vive todo lo necesario para levantar el entorno donde corren los microservicios, no el código de los microservicios en sí.

## 📋 ¿Para qué sirve este repo?

- Centraliza la configuración de **infraestructura compartida** (base de datos, mensajería, streaming) que usan varios microservicios a la vez.
- Permite levantar el **ecosistema completo** del proyecto clonando un solo repo, sin tener que pasar por cada `ms-campuslab-*` por separado.
- Separa lo que **cambia poco** (RabbitMQ, Kafka) de lo que **cambia seguido** (el código de las apps), evitando que un deploy de una app reinicie la infraestructura de mensajería.
- Refleja la separación real de instancias EC2 que propone el caso: `ec2-apps`, `ec2-mq`, `ec2-kafka` — cada una con su propio Security Group y ciclo de vida.

## 📦 Estructura

```
infra/
├── apim/
│   └── ...              # Azure API Management del BFF: scripts, políticas (CORS + JWT) y README
├── apps/
│   └── compose.yml      # orquesta los microservicios (bookings-svc, catalog-svc, notify-svc, report-svc, audit-svc)
├── mq/
│   ├── compose.yml      # RabbitMQ (clúster de 2 nodos) + Management UI
│   ├── rabbitmq.conf    # formación automática del clúster (peer discovery)
│   └── .env.example     # usuario, clave y cookie de Erlang (copiar a .env)
└── kafka/
    ├── compose.yml      # Zookeeper (3 nodos) + Kafka (3 brokers) + Kafka UI (pendiente de definir)
    └── compose.dev.yml  # Kafka de desarrollo: 1 broker KRaft, sin Zookeeper (para auditoría/reportería en local)
```

## 🚦 Cuándo usar cada compose

| Archivo | Se levanta cuando... | Frecuencia de cambio |
|---|---|---|
| `mq/compose.yml` | Se necesita RabbitMQ para notificaciones (colas `cmd.*`) | Baja — infraestructura estable |
| `kafka/compose.yml` | Se necesita Kafka para eventos/streaming (`bookings.events`, `audit.timeline`) | Baja — infraestructura estable |
| `apps/compose.yml` | Se despliega o actualiza alguno de los microservicios | Alta — cambia con cada release |

## 🚀 Uso

```bash
# Levantar mensajería
cd mq && docker compose up -d
docker exec campuslab-rabbitmq-1 rabbitmqctl cluster_status   # deben verse rabbit@rabbitmq-1 y rabbit@rabbitmq-2
# UI: nodo 1 http://localhost:15672 · nodo 2 http://localhost:15673 (usuario/clave por defecto: campuslab/campuslab)
# Los microservicios se conectan al nodo 1; con SPRING_RABBITMQ_ADDRESSES=localhost:5672,localhost:5673 toleran la caída de un nodo.
# ms-campuslab-notify/compose.yml también publica el 5672: no levantar ambos a la vez.

# Levantar streaming
cd kafka && docker compose up -d                  # clúster del proyecto (pendiente de definir)
# Para desarrollo local (auditoría, reportería): un solo broker KRaft
cd kafka && docker compose -f compose.dev.yml up -d

# Levantar las apps (requiere que mq/kafka ya estén arriba si las apps dependen de ellos)
cd apps && docker compose up -d
```

## 🔒 Security Groups (AWS EC2)

Al desplegar en EC2, abrir solo los puertos estrictamente necesarios:

| Instancia | Puertos a exponer |
|---|---|
| `ec2-mq` | AMQP `5672`, Management UI (según config) |
| `ec2-kafka` | Kafka `9092`, Kafka UI (según config) |
| `ec2-apps` | Puertos HTTP internos de cada microservicio (no exponer públicamente salvo lo que pase por API Gateway) |

## ⚠️ Qué NO va en este repo

- El `Dockerfile` de cada microservicio (vive en el propio repo del microservicio).
- Código de aplicación de cualquier tipo.
- Credenciales o secretos en texto plano — usar variables de entorno o un gestor de secretos.

## 🕓 Cuándo se creó / por qué

Este repo se incorpora al proyecto cuando una evaluación exige explícitamente RabbitMQ, Kafka o despliegue en EC2 — no es necesario mantenerlo desde el primer EP si esa evaluación aún no lo pide.

## 👥 Equipo

- *(completar con integrantes del equipo)*
# campuslab-infra
