#!/usr/bin/env bash
# ./send.sh <email|prep|voucher-retiro|voucher-devolucion|email-invalido|prep-invalido|voucher-invalido|ilegible>
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
node "$(win_path "$DEMO_DIR/send.js")" "$@"
