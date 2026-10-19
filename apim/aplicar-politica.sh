#!/usr/bin/env bash
# Aplica un archivo de politica XML a la API de CampusLab en APIM.
# Uso:  ./aplicar-politica.sh policy-v1.xml [api-id]      (api-id por defecto: campuslab-v1)
# Convierte el XML a JSON (escapa las comillas) para no hacerlo a mano.
set -euo pipefail
source ./apim.env

FILE=${1:?Uso: ./aplicar-politica.sh archivo.xml [api-id]}
API_ID=${2:-campuslab-v1}
SUB=$(az account show --query id -o tsv)

XML=$(tr -d '\r\n' < "$FILE" | sed 's/"/\\"/g')
printf '{"properties":{"format":"rawxml","value":"%s"}}' "$XML" > policy.json

az rest --method put \
  --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM/apis/$API_ID/policies/policy?api-version=2022-08-01" \
  --body @policy.json --output-file policy-response.json   # la respuesta de APIM trae BOM: imprimirla rompe az en Windows
echo "politica $FILE aplicada a $API_ID"
