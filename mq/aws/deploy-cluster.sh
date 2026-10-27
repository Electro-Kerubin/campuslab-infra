#!/usr/bin/env bash
# Clúster RabbitMQ de 2 nodos en AWS (EC2). Réplica del clúster local de ../compose.yml.
#
#   ./deploy-cluster.sh            # crea clave, security group y 2 instancias, y espera al clúster
#   ./destroy-cluster.sh           # lo borra todo (las instancias cuestan mientras estén encendidas)
#
# Diseño:
#   - 2 instancias Ubuntu 24.04 en zonas de disponibilidad distintas (us-east-2a y us-east-2b), con IP privada
#     fija: así el nombre de nodo (rabbit@ip-172-31-X-Y) se conoce antes de arrancar y ambos se encuentran solos.
#   - RabbitMQ 4.0 (misma imagen que el compose local) en Docker con red host.
#   - Security group: 22 / 5672 / 15672 solo desde tu IP; entre los nodos, todo el tráfico (epmd 4369,
#     distribución Erlang 25672, herramientas CLI 35672-35682).
#   - Secretos (clave SSH, usuario, contraseña y cookie de Erlang) en ~/.campuslab-aws/, FUERA del repositorio.
#
# Región: us-east-2 (el SCP de la organización niega EC2 en us-east-1 y us-west-2).
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash en Windows no debe reescribir rutas como /aws/service/...

REGION="${REGION:-us-east-2}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
PROJECT="campuslab-rabbitmq"
SECRETS_DIR="${SECRETS_DIR:-$HOME/.campuslab-aws}"
KEY_NAME="$PROJECT"
KEY_FILE="$SECRETS_DIR/$PROJECT.pem"
ENV_FILE="$SECRETS_DIR/rabbitmq.env"

# Nodo 1 en us-east-2a, nodo 2 en us-east-2b (subredes por defecto de la VPC por defecto)
AZ1="${AZ1:-us-east-2a}"; IP1="${IP1:-172.31.0.10}"
AZ2="${AZ2:-us-east-2b}"; IP2="${IP2:-172.31.16.10}"
HOST1="ip-${IP1//./-}"; HOST2="ip-${IP2//./-}"

aws_() { aws --region "$REGION" "$@"; }

mkdir -p "$SECRETS_DIR"; chmod 700 "$SECRETS_DIR" 2>/dev/null || true

# ---- Secretos: se generan una sola vez y se reutilizan ------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  {
    echo "RABBITMQ_USER=campuslab"
    echo "RABBITMQ_PASS=$(openssl rand -hex 16)"
    echo "RABBITMQ_ERLANG_COOKIE=$(openssl rand -hex 24)"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  echo "Secretos generados en $ENV_FILE"
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ---- Red y datos base ---------------------------------------------------------------------------
MY_IP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"
VPC_ID="$(aws_ ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
subnet_for() { aws_ ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$1" \
                 "Name=default-for-az,Values=true" --query 'Subnets[0].SubnetId' --output text; }
SUBNET1="$(subnet_for "$AZ1")"; SUBNET2="$(subnet_for "$AZ2")"
AMI="$(aws_ ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
        --query Parameter.Value --output text)"
echo "Región=$REGION  VPC=$VPC_ID  AMI=$AMI  tu IP=$MY_IP"

# ---- Clave SSH ----------------------------------------------------------------------------------
if ! aws_ ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  aws_ ec2 create-key-pair --key-name "$KEY_NAME" --key-type ed25519 --query KeyMaterial --output text | tr -d '\r' > "$KEY_FILE"
  chmod 600 "$KEY_FILE" 2>/dev/null || true
  echo "Clave SSH creada: $KEY_FILE"
fi

# ---- Security group -----------------------------------------------------------------------------
SG_ID="$(aws_ ec2 describe-security-groups --filters "Name=group-name,Values=$PROJECT" "Name=vpc-id,Values=$VPC_ID" \
          --query 'SecurityGroups[0].GroupId' --output text)"
if [ "$SG_ID" = "None" ]; then
  SG_ID="$(aws_ ec2 create-security-group --group-name "$PROJECT" --vpc-id "$VPC_ID" \
            --description "RabbitMQ cluster CampusLab" --query GroupId --output text)"
  for port in 22 5672 15672; do
    aws_ ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port "$port" --cidr "$MY_IP/32" >/dev/null
  done
  # Tráfico entre los nodos del clúster (el propio grupo como origen)
  aws_ ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 0-65535 --source-group "$SG_ID" >/dev/null
  aws_ ec2 create-tags --resources "$SG_ID" --tags Key=Name,Value="$PROJECT" Key=Project,Value=campuslab
  echo "Security group creado: $SG_ID"
fi

# ---- user-data: solo deja lista la máquina (Docker + compose); RabbitMQ lo levanta compose.yml -----
USER_DATA="$SECRETS_DIR/user-data.sh"
cat > "$USER_DATA" <<EOF
#!/bin/bash
set -eux
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y docker.io docker-compose-v2
systemctl enable --now docker
usermod -aG docker ubuntu
EOF

# aws.exe (Windows) no entiende rutas /c/... de Git Bash: convertir a C:/... si existe cygpath
USER_DATA_URI="$(command -v cygpath >/dev/null 2>&1 && cygpath -m "$USER_DATA" || echo "$USER_DATA")"

launch() { # nombre subnet ip
  aws_ ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" --key-name "$KEY_NAME" \
    --subnet-id "$2" --private-ip-address "$3" --security-group-ids "$SG_ID" --associate-public-ip-address \
    --metadata-options HttpTokens=required,HttpEndpoint=enabled \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3}' \
    --user-data "file://$USER_DATA_URI" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$1},{Key=Project,Value=campuslab}]" \
    --query 'Instances[0].InstanceId' --output text
}

EXISTING="$(aws_ ec2 describe-instances --filters "Name=tag:Project,Values=campuslab" "Name=tag:Name,Values=$PROJECT-*" \
             "Name=instance-state-name,Values=pending,running" --query 'Reservations[].Instances[].InstanceId' --output text)"
if [ -n "$EXISTING" ]; then
  echo "Ya existen instancias ($EXISTING); no se crean otras."
else
  I1="$(launch "$PROJECT-1" "$SUBNET1" "$IP1")"
  I2="$(launch "$PROJECT-2" "$SUBNET2" "$IP2")"
  echo "Instancias lanzadas: $I1 $I2"
fi
rm -f "$USER_DATA"

aws_ ec2 wait instance-running --filters "Name=tag:Project,Values=campuslab" "Name=tag:Name,Values=$PROJECT-*"
pub_ip() { aws_ ec2 describe-instances --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text; }
PUB1="$(pub_ip "$PROJECT-1")"; PUB2="$(pub_ip "$PROJECT-2")"
echo "Nodo 1: $PUB1 ($HOST1)   Nodo 2: $PUB2 ($HOST2)"

# ---- Ejecuta compose.yml en cada instancia (copia .env y 20-cluster.conf y hace docker compose up) ----
"$(dirname "${BASH_SOURCE[0]}")/apply-compose.sh"

# ---- Espera a que el clúster esté formado (API de gestión, 2 nodos en ejecución) -----------------
echo "Esperando a que los 2 nodos formen el clúster..."
for i in $(seq 1 60); do
  N="$(curl -s -m 5 -u "$RABBITMQ_USER:$RABBITMQ_PASS" "http://$PUB1:15672/api/nodes" 2>/dev/null \
        | grep -o '"running":true' | wc -l || true)"
  if [ "${N:-0}" -ge 2 ]; then echo "Clúster formado: 2 nodos en ejecución."; break; fi
  sleep 10
done

cat <<INFO

  Management UI nodo 1 : http://$PUB1:15672
  Management UI nodo 2 : http://$PUB2:15672
  AMQP                 : $PUB1:5672,$PUB2:5672
  Usuario / contraseña : ver $ENV_FILE
  SSH                  : ssh -i "$KEY_FILE" ubuntu@$PUB1
INFO
