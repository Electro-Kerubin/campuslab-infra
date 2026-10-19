#!/usr/bin/env bash
# Crea el resource group y la instancia de Azure API Management (tier Consumption).
# Uso (Git Bash):  cd campuslab-infra/apim && ./crear-apim.sh
# Si 'az' no está en el PATH de la terminal:  export PATH="$PATH:/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin"
set -euo pipefail

RG=${RG:-rg-campuslab-apim}
# Azure for Students solo permite: canadacentral, mexicocentral, brazilsouth, westus3, southafricanorth
LOC=${LOC:-brazilsouth}
APIM=${APIM:-apim-campuslab-$RANDOM}
ADMIN_EMAIL=${ADMIN_EMAIL:-rod.baeza@duocuc.cl}
ADMIN_NAME=${ADMIN_NAME:-Rodrigo Baeza}

# El nombre se guarda ANTES de crear, para no perderlo si la terminal se corta
printf "RG=%s\nLOC=%s\nAPIM=%s\n" "$RG" "$LOC" "$APIM" > apim.env

# idempotente: el grupo de recursos solo guarda metadatos, su region no limita la de los recursos
az group show -n "$RG" -o none 2>/dev/null || az group create -n "$RG" -l "$LOC" -o table
# Consumption: nunca Developer/Basic/Standard (gastan el crédito de estudiante)
az apim create -n "$APIM" -g "$RG" -l "$LOC" \
  --publisher-email "$ADMIN_EMAIL" --publisher-name "$ADMIN_NAME" \
  --sku-name Consumption -o table

echo "APIM creado: https://$APIM.azure-api.net   (datos en apim.env)"
