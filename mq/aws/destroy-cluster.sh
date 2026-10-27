#!/usr/bin/env bash
# Borra el clúster RabbitMQ de AWS (instancias, security group y clave SSH). Los secretos locales se conservan.
set -euo pipefail
export MSYS_NO_PATHCONV=1
REGION="${REGION:-us-east-2}"
PROJECT="campuslab-rabbitmq"
aws_() { aws --region "$REGION" "$@"; }

IDS="$(aws_ ec2 describe-instances --filters "Name=tag:Project,Values=campuslab" "Name=tag:Name,Values=$PROJECT-*" \
        "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)"
if [ -n "$IDS" ]; then
  aws_ ec2 terminate-instances --instance-ids $IDS >/dev/null
  echo "Terminando: $IDS"
  aws_ ec2 wait instance-terminated --instance-ids $IDS
fi
SG_ID="$(aws_ ec2 describe-security-groups --filters "Name=group-name,Values=$PROJECT" --query 'SecurityGroups[0].GroupId' --output text)"
[ "$SG_ID" != "None" ] && aws_ ec2 delete-security-group --group-id "$SG_ID" && echo "Security group borrado"
aws_ ec2 delete-key-pair --key-name "$PROJECT" && echo "Clave borrada en AWS (el .pem local queda en ~/.campuslab-aws)"
