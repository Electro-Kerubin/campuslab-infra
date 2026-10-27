#!/usr/bin/env bash
# Ejecuta demo-validacion.js contra mq-admin (puerto 8085) y el clúster de AWS
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
node "$(win_path "$DEMO_DIR/demo-validacion.js")"
