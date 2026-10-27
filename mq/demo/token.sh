#!/usr/bin/env bash
# Imprime el token ADMIN de demostración y lo copia al portapapeles (para el botón "Authorize" de Swagger).
# Uso: ./token.sh          (rol ADMIN)      ./token.sh tecnico   (rol TECNICO: mq-admin debe responder 403)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TOKEN="$(node "$(win_path "$DEMO_DIR/auth-local.js")" --print "${1:-admin}")" || { echo "Primero ejecuta ./start-mq-admin.sh"; exit 1; }
echo "$TOKEN"
if command -v clip >/dev/null 2>&1; then printf '%s' "$TOKEN" | clip && echo "(copiado al portapapeles)" >&2; fi
