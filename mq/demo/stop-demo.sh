#!/usr/bin/env bash
# Detiene lo que levantó el kit (notify, mq-admin y el emisor de tokens). No toca el clúster de AWS.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
kill_port 8084; kill_port 8085; kill_port 18999
echo "Demo detenida. El clúster de AWS sigue encendido (./../aws/destroy-cluster.sh lo borra)."
