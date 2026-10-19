#!/usr/bin/env bash
# Publica el BFF en APIM como API versionada (/campuslab/v1) con operaciones comodin.
# Uso:  BFF_URL=https://campuslab-bff-8080.brs.devtunnels.ms ./configurar-api.sh
# BFF_URL es la URL publica del BFF, SIN "/api" ni "/" final. Es idempotente: si la API ya existe, la actualiza
# (sirve para cambiar el backend cuando cambia la URL del tunel).
set -euo pipefail
source ./apim.env
: "${BFF_URL:?Defina BFF_URL (URL publica del BFF, sin /api ni / final)}"
API_PATH=campuslab
API_ID=campuslab-v1
SUB=$(az account show --query id -o tsv)
BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM"

az apim api versionset create -g "$RG" --service-name "$APIM" \
  --version-set-id campuslab-vs --display-name "CampusLab" --versioning-scheme Segment -o none

# 'az apim api create' de este CLI no tiene flags de versionado: se crea por la API REST de Azure
printf '{"properties":{"displayName":"CampusLab BFF v1","path":"%s","serviceUrl":"%s","protocols":["https"],"subscriptionRequired":false,"apiVersion":"v1","apiVersionSetId":"%s/apiVersionSets/campuslab-vs"}}' \
  "$API_PATH" "$BFF_URL" "${BASE#https://management.azure.com}" > api.json
az rest --method put --url "$BASE/apis/$API_ID?api-version=2022-08-01" --body @api.json --query "properties.path" -o tsv

# Una operacion comodin por verbo cubre todas las rutas del BFF; OPTIONS permite resolver el preflight
for M in GET POST PUT PATCH DELETE OPTIONS; do
  az apim api operation create -g "$RG" --service-name "$APIM" --api-id "$API_ID" \
    --operation-id "proxy-$(echo "$M" | tr 'A-Z' 'a-z')" --display-name "$M (todas las rutas)" \
    --method "$M" --url-template "/*" -o none
done

echo "API publicada: https://$APIM.azure-api.net/$API_PATH/v1/api/...  ->  $BFF_URL/api/..."
